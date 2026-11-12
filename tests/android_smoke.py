"""Install and exercise the release APK on an already booted, isolated emulator.

Requires Pillow. Intentionally refuses physical Android devices.
Reads private tool paths from build/toolchain/env.json without printing secrets.
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
import subprocess
import time
from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--serial', default='emulator-5556')
args = parser.parse_args()
if not args.serial.startswith('emulator-'):
    raise SystemExit('This test only runs against an isolated emulator.')
cfg = json.loads((ROOT / 'build/toolchain/env.json').read_text(encoding='utf-8-sig'))
ADB = str(Path(cfg['android_sdk']) / 'platform-tools/adb.exe')
OUT = ROOT / 'build/android-native'
OUT.mkdir(parents=True, exist_ok=True)
checks = []

def adb(*command):
    result = subprocess.run([ADB, '-s', args.serial, *command], capture_output=True, timeout=90)
    if result.returncode:
        raise RuntimeError(result.stderr.decode('utf-8', 'replace'))
    return result.stdout

def check(value, label):
    checks.append({'check': label, 'passed': bool(value)})
    if not value:
        raise AssertionError(label)

def shot(name):
    data = adb('exec-out', 'screencap', '-p')
    (OUT / f'{name}.png').write_bytes(data)
    return Image.open(io.BytesIO(data)).convert('RGB')

def level(image):
    w, h = image.size
    scale = h / 208
    left = (w - 256 * scale) / 2
    return image.crop((int(left), 0, int(left + 256 * scale), int(144 * scale)))

def brightness(image):
    return ImageStat.Stat(image.convert('L')).mean[0]

def tap(x, y):
    adb('shell', 'input', 'tap', str(round(x)), str(round(y)))
    time.sleep(.4)

try:
    check(adb('shell', 'getprop', 'sys.boot_completed').strip() == b'1', 'Android emulator completed boot')
    installed = adb('install', '-r', str(ROOT / 'dist/Android/Warma.apk'))
    check(b'Success' in installed, 'Release APK installs successfully')
    adb('shell', 'am', 'force-stop', 'org.warma.performmusic')
    adb('logcat', '-c')
    adb('shell', 'am', 'start', '-n', 'org.warma.performmusic/com.godot.game.GodotApp')
    time.sleep(3)
    title = shot('title')
    w, h = title.size
    check(w > h, 'Native application starts in landscape')
    tap(w / 2, h * .68)
    gameplay = shot('gameplay')
    check(brightness(level(gameplay)) > 80, 'Gameplay is visibly rendered')
    scale = h / 208
    x, y = 64 * scale, h - 19 * scale
    adb('shell', 'input', 'swipe', str(round(x)), str(round(y)), str(round(x)), str(round(y)), '450')
    time.sleep(.3)
    moved = shot('movement')
    change = sum(ImageStat.Stat(ImageChops.difference(level(gameplay), level(moved))).mean)
    check(change > .1, 'Touch direction button moves the player')
    adb('shell', 'input', 'keyevent', '4')
    time.sleep(.8)
    paused = shot('back-paused')
    check(brightness(level(paused)) < brightness(level(moved)) * .7, 'One Android Back press pauses exactly once')
    adb('shell', 'input', 'keyevent', '4')
    time.sleep(.8)
    resumed = shot('back-resumed')
    check(brightness(level(resumed)) > brightness(level(paused)) * 1.3, 'Next Android Back press resumes')
    adb('shell', 'input', 'keyevent', '3')
    time.sleep(.4)
    adb('shell', 'am', 'start', '-n', 'org.warma.performmusic/com.godot.game.GodotApp')
    time.sleep(.8)
    background = shot('background-paused')
    check(brightness(level(background)) < brightness(level(resumed)) * .7, 'Returning from background stays paused')
    tap(w - 31 * scale, h - 49 * scale)
    after_touch = shot('touch-resumed')
    check(brightness(level(after_touch)) > brightness(level(background)) * 1.3, 'Touch Continue button resumes')
    log = adb('logcat', '-d', '-s', 'godot', 'AndroidRuntime').decode('utf-8', 'replace')
    (OUT / 'runtime.log').write_text(log, encoding='utf-8')
    check('SCRIPT ERROR:' not in log and 'FATAL EXCEPTION' not in log, 'No GDScript errors or Android crashes')
finally:
    with (ROOT / 'dist/Android/Warma.apk').open('rb') as stream:
        apk_sha256 = hashlib.file_digest(stream, 'sha256').hexdigest()
    (OUT / 'report.json').write_text(json.dumps({'apk_sha256': apk_sha256, 'device': args.serial, 'checks': checks}, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'ANDROID_SMOKE: {len(checks)} checks passed')
