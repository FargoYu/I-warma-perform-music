"""Exercise the standalone HTML using file:// with all HTTP networking disabled.

Requires Playwright and Pillow. No local server or browser security flags used.
The only Chromium flag enables its software WebGL renderer in headless testing.
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
from PIL import Image, ImageChops, ImageStat
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--html", type=Path, default=ROOT / "dist/Web/index.html")
parser.add_argument("--browser", default=r"C:\Program Files\Google\Chrome\Application\chrome.exe")
args = parser.parse_args()
OUT = ROOT / "build/offline-browser"
OUT.mkdir(parents=True, exist_ok=True)
checks, errors, requests, console = [], [], [], []


def check(value, label):
    checks.append({"check": label, "passed": bool(value)})
    if not value:
        raise AssertionError(label)


def shot(page, label):
    return Image.open(io.BytesIO(page.screenshot(path=str(OUT / f"{label}.png")))).convert("RGB")


def difference(a, b):
    return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3


def brightness(image):
    return ImageStat.Stat(image.convert("L")).mean[0]


def point(width, height, action):
    scale = min(width / 256, height / 208)
    logical_width, logical_height = width / scale, height / scale
    x, y = {"right": (64, logical_height - 19), "jump": (logical_width - 27, logical_height - 19),
            "pause": (logical_width - 31, logical_height - 49)}[action]
    return x * scale, y * scale


def load(context, label):
    context.set_offline(True)
    page = context.new_page()
    page.on("request", lambda req: requests.append(req.url))
    page.on("pageerror", lambda error: errors.append(f"{label}: {error}"))
    def capture(msg):
        console.append({"page": label, "type": msg.type, "text": msg.text})
        if msg.type == "error" or "SCRIPT ERROR:" in msg.text or "ERROR:" in msg.text:
            errors.append(f"{label}: {msg.text}")
    page.on("console", capture)
    page.add_init_script("""
      window.__originalFetch = window.fetch;
      window.__contexts = []; window.__workletLoads = []; window.__outputNodes = [];
      const NativeContext = window.AudioContext;
      window.AudioContext = new Proxy(NativeContext, {
        construct(target, args, ctor) {
          const ctx = Reflect.construct(target, args, ctor);
          window.__contexts.push(ctx);
          const add = ctx.audioWorklet.addModule.bind(ctx.audioWorklet);
          ctx.audioWorklet.addModule = (url, opts) => add(url, opts).then(() => {
            window.__workletLoads.push(url.startsWith('data:') ? 'embedded' : url);
          });
          return ctx;
        }
      });
      const connect = AudioNode.prototype.connect;
      AudioNode.prototype.connect = function(destination, ...args) {
        const result = connect.call(this, destination, ...args);
        if (destination instanceof AudioDestinationNode) window.__outputNodes.push(this);
        return result;
      };
    """)
    page.goto(args.html.resolve().as_uri(), wait_until="domcontentloaded", timeout=120000)
    page.wait_for_function("document.getElementById('loading').hidden", timeout=120000)
    page.wait_for_timeout(400)
    check(page.url.startswith("file:///"), f"{label}: opened directly as a local HTML file")
    check(page.evaluate("window.fetch === window.__originalFetch"), f"{label}: browser fetch remains unchanged")
    check(page.locator("canvas").evaluate("c => c.width > 0 && c.height > 0"), f"{label}: WebGL canvas initialized offline")
    return page


try:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(executable_path=args.browser, headless=True,
                                             args=["--enable-unsafe-swiftshader"])
        desktop = browser.new_context(viewport={"width": 1024, "height": 576})
        page = load(desktop, "desktop")
        title = shot(page, "desktop-title")
        page.mouse.click(512, 340)
        page.wait_for_timeout(500)
        gameplay = shot(page, "desktop-gameplay")
        check(difference(title, gameplay) > 10, "Local HTML click starts the game")
        page.keyboard.down("d"); page.keyboard.down("j")
        page.wait_for_timeout(180)
        page.keyboard.up("d"); page.keyboard.up("j")
        moving = shot(page, "desktop-moving")
        check(difference(gameplay, moving) > .05, "Keyboard movement and jumping work offline")
        page.keyboard.press("p"); page.wait_for_timeout(150)
        paused = shot(page, "desktop-paused")
        check(brightness(paused) < brightness(moving) - 10, "Keyboard pause works offline")
        page.keyboard.press("Escape"); page.keyboard.press("r")
        page.wait_for_timeout(400)
        check(difference(gameplay, shot(page, "desktop-restarted")) < 2, "Keyboard restart works offline")
        page.wait_for_function("__contexts.length > 0 && __contexts.every(c => c.state === 'running')", timeout=5000)
        check(page.evaluate("__contexts.every(c => c.state === 'running')"), "User gesture unlocks normal browser audio")
        check(page.evaluate("__workletLoads.length > 0 && __workletLoads.every(x => x === 'embedded')"), "Embedded audio worklets load from local HTML")
        page.evaluate("""() => {
          window.__analysers = __outputNodes.map(node => {
            const analyser = node.context.createAnalyser();
            node.connect(analyser); return analyser;
          });
        }""")
        page.wait_for_function("""__analysers.some(analyser => {
          const data = new Float32Array(analyser.fftSize);
          analyser.getFloatTimeDomainData(data);
          return data.some(value => Math.abs(value) > 0.00001);
        })""", timeout=5000)
        check(True, "Game produces a non-silent audio signal offline")
        for _ in range(24):
            page.keyboard.press("m"); page.wait_for_timeout(130)
        page.wait_for_timeout(300)
        check(difference(title, shot(page, "desktop-completed")) > 5, "All 24 offline rooms reach the ending")
        page.mouse.click(512, 340); page.wait_for_timeout(300)
        check(difference(title, shot(page, "desktop-returned-title")) < 2, "Offline game returns to title for replay")
        desktop.close()

        mobile = browser.new_context(viewport={"width": 960, "height": 540}, has_touch=True, is_mobile=True,
                                    device_scale_factor=1)
        page = load(mobile, "mobile emulation")
        page.touchscreen.tap(480, 300); page.wait_for_timeout(400)
        landscape = shot(page, "mobile-landscape")
        check(landscape.getpixel((2, 535)) == (19, 35, 49), "Offline touch controls appear below the full game")
        cdp = mobile.new_cdp_session(page)
        right, jump = point(960, 540, "right"), point(960, 540, "jump")
        cdp.send("Input.dispatchTouchEvent", {"type": "touchStart", "touchPoints": [
            {"id": 1, "x": right[0], "y": right[1]}, {"id": 2, "x": jump[0], "y": jump[1]}]})
        page.wait_for_timeout(180)
        multi = shot(page, "mobile-multitouch")
        cdp.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
        check(difference(landscape, multi) > .05, "Local HTML handles simultaneous movement and jump touches")
        page.touchscreen.tap(*point(960, 540, "pause")); page.wait_for_timeout(150)
        check(brightness(shot(page, "mobile-paused")) < brightness(multi) - 10, "Offline touch pause works")
        page.touchscreen.tap(*point(960, 540, "pause")); page.wait_for_timeout(150)
        page.set_viewport_size({"width": 540, "height": 960}); page.wait_for_timeout(300)
        portrait = shot(page, "mobile-portrait")
        check(portrait.getpixel((2, 955)) == (19, 35, 49), "Offline touch layout survives portrait rotation")
        check(page.locator("#orientation").is_visible(), "Offline portrait shows landscape hint")
        mobile.close(); browser.close()
    check(not any(url.startswith(("http:", "https:")) for url in requests), "No HTTP or HTTPS requests: the single HTML is self-contained")
    check(not errors, "No JavaScript, GDScript, audio, or browser errors")
finally:
    with args.html.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    report = {"html": str(args.html.resolve()), "sha256": digest, "checks": checks, "errors": errors,
              "requests": requests, "console": console, "scope": "Actual file:// in desktop Chrome plus touch emulation; no Android-device claim."}
    (OUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"OFFLINE_WEB_SMOKE: {sum(c['passed'] for c in checks)}/{len(checks)} checks; {len(errors)} errors")
