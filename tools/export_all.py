"""Rebuild distributables using Godot 4.7.2 and the local Android toolchain."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--godot", help="Path to a Godot 4.7.2 editor executable")
parser.add_argument("--platform", choices=["all", "windows", "android", "web"], default="all")
args = parser.parse_args()
local_config = ROOT / "build/toolchain/env.json"
settings = json.loads(local_config.read_text(encoding="utf-8-sig")) if local_config.exists() else {}
godot = args.godot or settings.get("godot") or shutil.which("godot.windows.opt.tools.64.exe") or shutil.which("godot")
if not godot:
    sys.exit("Godot editor not found. Pass --godot PATH.")
env = os.environ.copy()
for key, variable in [("java_home", "JAVA_HOME"), ("android_sdk", "ANDROID_HOME"),
                      ("keystore", "GODOT_ANDROID_KEYSTORE_RELEASE_PATH"),
                      ("keystore_alias", "GODOT_ANDROID_KEYSTORE_RELEASE_USER"),
                      ("keystore_password", "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD")]:
    if settings.get(key):
        env[variable] = settings[key]
if env.get("JAVA_HOME"):
    env["PATH"] = str(Path(env["JAVA_HOME"]) / "bin") + os.pathsep + env["PATH"]

build_dir = ROOT / "build"
build_dir.mkdir(exist_ok=True)
def run(label, *command):
    print(label, flush=True)
    result = subprocess.run([str(godot), "--headless", "--path", str(ROOT), *command], cwd=ROOT,
                            env=env, capture_output=True, text=True, encoding="utf-8", errors="replace")
    log = result.stdout + result.stderr
    (build_dir / f"{label}.log").write_text(log, encoding="utf-8")
    if result.returncode or "SCRIPT ERROR:" in log or "ERROR:" in log:
        print(log[-8000:])
        sys.exit(f"{label} failed. See build/{label}.log")

run("import", "--editor", "--import", "--quit")
presets = [("windows", "Windows Desktop", "Windows", "Warma.exe"),
           ("android", "Android", "Android", "Warma.apk"),
           ("web", "Web", "Web", "index.html")]
for key, preset, folder, filename in presets:
    if args.platform not in ("all", key):
        continue
    destination = ROOT / "dist" / folder
    destination.mkdir(parents=True, exist_ok=True)
    if key == "web":
        runtime = ROOT / "build/web-runtime"
        runtime.mkdir(parents=True, exist_ok=True)
        run("export-web", "--export-release", preset, str(runtime / filename))
        shutil.copy2(ROOT / "Assets/Fonts/OFL.txt", runtime / "FONT-LICENSE.txt")
        subprocess.run([sys.executable, str(ROOT / "tools/make_standalone_web.py"),
                        "--source", str(runtime), "--output", str(destination)], check=True)
        # Remove only obsolete files from our former multi-file web export.
        for name in ("index.js", "index.wasm", "index.pck", "index.png", "index.icon.png",
                     "index.apple-touch-icon.png", "index.audio.worklet.js",
                     "index.audio.position.worklet.js", "Start-Web.cmd", "serve.py"):
            (destination / name).unlink(missing_ok=True)
    else:
        run(f"export-{key}", "--export-release", preset, str(destination / filename))
    if not (destination / filename).is_file() or (destination / filename).stat().st_size == 0:
        sys.exit(f"Missing output: {destination / filename}")
    shutil.copy2(ROOT / "Assets/Fonts/OFL.txt", destination / "FONT-LICENSE.txt")
    shutil.copy2(ROOT / "platform" / f"{key}-README.txt", destination / "README.txt")
    for notice in (ROOT / "licenses").glob("*.txt"):
        shutil.copy2(notice, destination / notice.name)
    shutil.copy2(ROOT / "THIRD_PARTY_NOTICES.txt", destination / "THIRD_PARTY_NOTICES.txt")
    hashes = []
    for file in sorted(destination.iterdir()):
        if file.is_file() and file.name != "SHA256SUMS.txt" and not file.name.endswith(".idsig"):
            with file.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            hashes.append(f"{digest}  {file.name}")
    (destination / "SHA256SUMS.txt").write_text("\n".join(hashes) + "\n", encoding="utf-8")
    print(f"Ready: {destination}", flush=True)
print("Export complete.")
