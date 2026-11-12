"""Exercise the exported Web build in Chromium with real WebGL and touch input.

Requires Playwright and Pillow. Run: python tests/web_smoke.py
Outputs screenshots and a JSON report under build/browser/.
"""
from pathlib import Path
import argparse
import io
import json
import socket
import subprocess
import sys
import time
from PIL import Image, ImageChops, ImageStat
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/browser"
OUT.mkdir(parents=True, exist_ok=True)
parser = argparse.ArgumentParser()
parser.add_argument("--browser", default=r"C:\Program Files\Google\Chrome\Application\chrome.exe")
parser.add_argument("--port", type=int, default=8061)
args = parser.parse_args()
results = []
errors = []
console = []


def check(condition, message):
    results.append({"check": message, "passed": bool(condition)})
    if not condition:
        raise AssertionError(message)


def shot(page, name):
    data = page.screenshot(path=str(OUT / f"{name}.png"))
    return Image.open(io.BytesIO(data)).convert("RGB")


def difference(first, second):
    return sum(ImageStat.Stat(ImageChops.difference(first, second)).mean) / 3


def brightness(image):
    return ImageStat.Stat(image.convert("L")).mean[0]


def load_page(context, label):
    page = context.new_page()
    page.on("pageerror", lambda error: errors.append(f"{label}: {error}"))

    def capture(message):
        console.append({"page": label, "type": message.type, "text": message.text})
        if message.type == "error" or "SCRIPT ERROR:" in message.text or "ERROR:" in message.text:
            errors.append(f"{label}: {message.text}")

    page.on("console", capture)
    page.goto(f"http://127.0.0.1:{args.port}/", wait_until="domcontentloaded")
    page.wait_for_function("document.getElementById('loading').hidden === true", timeout=120000)
    page.wait_for_timeout(500)
    check(page.locator("canvas").evaluate("c => c.width > 0 && c.height > 0"), f"{label}: engine canvas is initialized")
    check(page.evaluate("!crossOriginIsolated"), f"{label}: single-threaded export works without cross-origin isolation")
    return page


def touch_point(width, height, action):
    scale = min(width / 256, height / 208)
    logical_width = width / scale
    logical_height = height / scale
    centers = {
        "left": (24, logical_height - 19),
        "right": (64, logical_height - 19),
        "jump": (logical_width - 27, logical_height - 19),
        "shoot": (logical_width - 73, logical_height - 19),
        "pause": (logical_width - 31, logical_height - 49),
        "restart": (logical_width - 85, logical_height - 49),
    }
    x, y = centers[action]
    return x * scale, y * scale


def mobile_tap(page, action):
    box = page.locator("canvas").bounding_box()
    x, y = touch_point(box["width"], box["height"], action)
    page.touchscreen.tap(box["x"] + x, box["y"] + y)
    page.wait_for_timeout(150)


def level_crop(image):
    width, height = image.size
    scale = min(width / 256, height / 208)
    left = (width - 256 * scale) / 2
    top = (height - 208 * scale) / 2
    return image.crop((round(left), round(top), round(left + 256 * scale), round(top + 144 * scale)))


server_log = (OUT / "server.log").open("w", encoding="utf-8")
server = None
try:
    with socket.socket() as sock:
        check(sock.connect_ex(("127.0.0.1", args.port)) != 0, "Dedicated preview server port is available")
    server = subprocess.Popen([sys.executable, str(ROOT / "tools/serve_web.py"), "--no-browser", "--port", str(args.port)],
                              stdout=server_log, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + 10
    while True:
        with socket.socket() as sock:
            if sock.connect_ex(("127.0.0.1", args.port)) == 0:
                break
        if time.monotonic() > deadline or server.poll() is not None:
            raise RuntimeError("Preview server did not start")
        time.sleep(0.1)
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(executable_path=args.browser, headless=True,
                    args=["--enable-unsafe-swiftshader"])
        desktop = browser.new_context(viewport={"width": 1024, "height": 576}, device_scale_factor=1)
        page = load_page(desktop, "desktop")
        title = shot(page, "desktop-title")
        page.mouse.click(512, 340)
        page.wait_for_timeout(400)
        gameplay = shot(page, "desktop-gameplay")
        check(difference(title, gameplay) > 10, "Desktop click enters gameplay")
        page.keyboard.down("d")
        page.keyboard.down("j")
        page.wait_for_timeout(180)
        page.keyboard.up("d")
        page.keyboard.up("j")
        moving = shot(page, "desktop-moving")
        check(difference(gameplay, moving) > 0.05, "Desktop keyboard movement changes rendered game")
        page.keyboard.press("p")
        page.wait_for_timeout(150)
        paused = shot(page, "desktop-paused")
        check(brightness(paused) < brightness(moving) - 10, "Desktop pause visibly dims the game")
        page.keyboard.press("Escape")
        page.keyboard.press("r")
        page.wait_for_timeout(550)
        restarted = shot(page, "desktop-restarted")
        check(difference(gameplay, restarted) < 2, "Keyboard restart restores first-room appearance")
        for _ in range(24):
            page.keyboard.press("m")
            page.wait_for_timeout(130)
        completed = shot(page, "desktop-completed")
        check(difference(completed, title) > 5, "Completing 24 rooms displays a distinct completion screen")
        page.wait_for_timeout(300)
        page.mouse.click(512, 340)
        page.wait_for_timeout(250)
        returned = shot(page, "desktop-returned-title")
        check(difference(title, returned) < 2, "Completion returns to the original title without closing Web runtime")
        check(page.locator("#loading").is_hidden(), "Web runtime remains active after completion")
        desktop.close()

        mobile = browser.new_context(viewport={"width": 960, "height": 540}, device_scale_factor=1,
                    is_mobile=True, has_touch=True,
                    user_agent="Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36")
        page = load_page(mobile, "mobile")
        shot(page, "mobile-title")
        page.touchscreen.tap(480, 300)
        page.wait_for_timeout(400)
        mobile_game = shot(page, "mobile-landscape")
        check(mobile_game.getpixel((2, 535)) == (19, 35, 49), "Mobile touch control deck is rendered below game")
        cdp = mobile.new_cdp_session(page)
        right = touch_point(960, 540, "right")
        jump = touch_point(960, 540, "jump")
        cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [
            {"id": 1, "x": right[0], "y": right[1]}, {"id": 2, "x": jump[0], "y": jump[1]}]})
        page.wait_for_timeout(180)
        multi = shot(page, "mobile-multitouch")
        cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
        check(difference(level_crop(mobile_game), level_crop(multi)) > 0.05, "Simultaneous browser touches move and jump in gameplay")
        mobile_tap(page, "pause")
        mobile_paused = shot(page, "mobile-paused")
        check(brightness(level_crop(mobile_paused)) < brightness(level_crop(multi)) - 10, "Touch pause visibly dims gameplay")
        mobile_tap(page, "pause")
        mobile_tap(page, "restart")
        page.wait_for_timeout(550)
        check(difference(level_crop(mobile_game), level_crop(shot(page, "mobile-restarted"))) < 2, "Touch restart restores first room")
        page.set_viewport_size({"width": 540, "height": 960})
        page.wait_for_timeout(500)
        portrait = shot(page, "mobile-portrait")
        check(portrait.getpixel((2, 955)) == (19, 35, 49), "Portrait resize keeps the control deck at bottom")
        check(page.locator("#orientation").is_visible(), "Portrait displays landscape recommendation")
        mobile_tap(page, "pause")
        portrait_paused = shot(page, "mobile-portrait-paused")
        check(brightness(level_crop(portrait_paused)) < brightness(level_crop(portrait)) - 10, "Touch controls remain usable after portrait resize")
        mobile_tap(page, "pause")
        # Headless Chromium keeps all tabs visible, so dispatch the browser
        # background signal explicitly; real Android backgrounding is covered
        # separately in the device smoke check.
        page.evaluate("window.dispatchEvent(new Event('blur'))")
        page.wait_for_timeout(250)
        background_paused = shot(page, "mobile-return-from-background")
        check(brightness(level_crop(background_paused)) < brightness(level_crop(portrait)) - 10, "Browser window blur pauses the puzzle")
        page.set_viewport_size({"width": 960, "height": 540})
        # CSS env() values cannot be set by device emulation. Override the
        # equivalent CSS variables to simulate a left cutout and gesture bar.
        page.evaluate("""() => {
            const style = document.documentElement.style;
            style.setProperty('--safe-left', '36px');
            style.setProperty('--safe-right', '12px');
            style.setProperty('--safe-bottom', '24px');
        }""")
        page.wait_for_timeout(350)
        safe_box = page.locator("canvas").bounding_box()
        check(safe_box == {"x": 36, "y": 0, "width": 912, "height": 516}, "Canvas excludes simulated cutout and gesture areas")
        check(page.locator("canvas").evaluate("c => c.width === 912 && c.height === 516"), "Godot backing buffer matches usable canvas size")
        safe_paused = Image.open(io.BytesIO(page.locator("canvas").screenshot())).convert("RGB")
        mobile_tap(page, "pause")
        safe_playing = Image.open(io.BytesIO(page.locator("canvas").screenshot())).convert("RGB")
        check(brightness(level_crop(safe_playing)) > brightness(level_crop(safe_paused)) + 10, "Touch hit coordinates stay correct inside safe-area insets")
        shot(page, "mobile-safe-area")
        page.locator("#fullscreen").click()
        page.wait_for_function("Boolean(document.fullscreenElement)", timeout=5000)
        check(page.locator("#fullscreen").inner_text() == "退出全屏", "Fullscreen button enters fullscreen and updates its label")
        page.locator("#fullscreen").click()
        page.wait_for_function("!document.fullscreenElement", timeout=5000)
        check(page.locator("#fullscreen").inner_text() == "全屏", "Fullscreen button exits fullscreen without closing game")
        check(page.locator("#loading").is_hidden(), "Mobile game survives rotation, backgrounding, safe area and fullscreen changes")
        mobile.close()
        hidpi = browser.new_context(viewport={"width": 412, "height": 915}, device_scale_factor=3,
                                   is_mobile=True, has_touch=True)
        page = load_page(hidpi, "mobile-hidpi")
        check(page.locator("canvas").evaluate("c => c.width === 824 && c.height === 1830"), "High-density phone uses bounded 2x canvas resolution")
        page.touchscreen.tap(206, 450)
        page.wait_for_timeout(400)
        hidpi_game = Image.open(io.BytesIO(page.locator("canvas").screenshot())).convert("RGB")
        mobile_tap(page, "pause")
        hidpi_paused = Image.open(io.BytesIO(page.locator("canvas").screenshot())).convert("RGB")
        check(brightness(level_crop(hidpi_paused)) < brightness(level_crop(hidpi_game)) - 10, "High-density Android touch coordinates pause the game correctly")
        shot(page, "mobile-hidpi")
        hidpi.close()
        browser.close()
    check(not errors, "No JavaScript, GDScript, or browser console errors")
finally:
    if server is not None:
        server.terminate()
        server.wait(timeout=10)
    server_log.close()
    (OUT / "report.json").write_text(json.dumps({"checks": results, "errors": errors, "console": console}, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"WEB_SMOKE: {sum(item['passed'] for item in results)}/{len(results)} checks passed; {len(errors)} browser errors")
    print(f"Artifacts: {OUT}")
