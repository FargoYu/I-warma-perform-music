"""Bundle a Godot 4.7.2 single-threaded Web export into an offline HTML file.

No server, browser flags, CDN, global fetch override, or service worker is used.
Only generated engine asset loading and its file-origin PWA query are adapted. Strict
match counts make a different/incompatible engine template fail explicitly.
"""
from pathlib import Path
import argparse
import base64
import gzip
import hashlib
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Expected exactly one Godot template marker: {old[:80]!r}")
    return text.replace(old, new, 1)


def script(source):
    # Embedded JS strings must never prematurely terminate their HTML element.
    return "<script>\n" + re.sub(r"</script", r"<\\/script", source, flags=re.I) + "\n</script>"


def build(source, destination):
    source = source.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    html = (source / "index.html").read_text(encoding="utf-8")
    engine = (source / "index.js").read_text(encoding="utf-8")
    loader = (ROOT / "platform/web/standalone-loader.js").read_text(encoding="utf-8")
    assets = []
    for name in ("index.wasm", "index.pck"):
        raw = (source / name).read_bytes()
        encoded = base64.b64encode(gzip.compress(raw, compresslevel=9, mtime=0)).decode("ascii")
        mime = "application/wasm" if name.endswith("wasm") else "application/octet-stream"
        assets.append(f'<script type="application/octet-stream" id="embedded-{name}" data-mime="{mime}" data-size="{len(raw)}">{encoded}</script>')
    for name in ("index.audio.worklet.js", "index.audio.position.worklet.js"):
        encoded = base64.b64encode((source / name).read_bytes()).decode("ascii")
        assets.append(f'<script type="application/octet-stream" id="embedded-{name}" data-mime="text/javascript">{encoded}</script>')

    # The first patch changes only this game's engine preloader, leaving browser
    # fetch and all other scripts untouched. Worklets use embedded data URLs.
    engine = replace_once(engine, "return fetch(file).then(function (response) {", "return WarmaEmbedded.response(file).then(function (response) {")
    for ending in ("audio.worklet.js", "audio.position.worklet.js"):
        engine = replace_once(engine, f"return `${{loadPath}}.{ending}`;", f'return WarmaEmbedded.workletURL("index.{ending}");')
    engine = replace_once(engine,
        'if("serviceWorker"in navigator){try{const cb=GodotRuntime.get_func(p_update_cb);',
        'if(location.protocol!=="file:"&&"serviceWorker"in navigator){try{const cb=GodotRuntime.get_func(p_update_cb);')
    html = replace_once(html, '<script src="index.js"></script>', "\n".join(assets) + "\n" + script(loader) + "\n" + script(engine))
    # Match the local-file branch independent of its user-facing message. The
    # standalone version reads embedded bytes and never fetches adjacent files.
    html, count = re.subn(r"if \(location\.protocol === 'file:'\) \{\s*fail\(new Error\([^\n]*\)\);\s*\} else \{", "{", html)
    if count != 1:
        raise ValueError("Expected one local-file guard in the normal Web shell")
    html = replace_once(html, "const missing = Engine.getMissingFeatures({ threads: false });", "const missing = Engine.getMissingFeatures({ threads: false });\n        if (typeof DecompressionStream === 'undefined') missing.push('解压支持：请更新浏览器');")
    # This game has no persistent saves, so avoid local-origin IndexedDB quirks.
    html = replace_once(html, "const engine = new Engine(config);", "const engine = new Engine({ ...config, persistentPaths: [] });")
    html = replace_once(html, "document.getElementById('loading').hidden = true;", "WarmaEmbedded.releaseLoadedData();\n          document.getElementById('loading').hidden = true;")
    html = html.replace("并确认所有导出文件位于同一目录", "若仍无法启动，请重新下载完整的 HTML 文件")
    html = html.replace("正在加载游戏…", "正在准备游戏…")
    for name in ("index.icon.png", "index.apple-touch-icon.png"):
        encoded = base64.b64encode((source / name).read_bytes()).decode("ascii")
        html = html.replace(f'href="{name}"', f'href="data:image/png;base64,{encoded}"')
    output = destination / "index.html"
    output.write_text(html, encoding="utf-8")
    shutil.copy2(source / "FONT-LICENSE.txt", destination / "FONT-LICENSE.txt")
    (destination / "README.txt").write_text(
        "沃要吹灭火器 v1.3 — 直接打开的单文件网页版\n\n"
        "双击 index.html，使用新版 Chrome、Edge 或 Firefox 打开即可开始。\n"
        "不需要 CMD、Python、本地服务器或联网；请先从压缩包完整解压。\n"
        "引擎、关卡、中文字体、图片和音频均已包含在 HTML 内，首次打开请等加载完成。\n"
        "第一次点击/按键/触摸后浏览器才会开启音频，这是正常的自动播放限制。\n\n"
        "同一 HTML 也可以直接上传到 GitHub Pages 等 HTTPS 静态网站。\n"
        "安卓手机访问网站后自动显示多点触屏按钮，推荐横屏。\n"
        "手机文件管理器可能用不支持WebGL的预览器打开本地HTML，此时请改用浏览器，\n"
        "或者通过托管网站的网址游玩。无需安装APK。\n\n"
        "电脑：A/D移动，J跳跃，K演奏，W进门，R重来，P/Esc暂停，左右方向键调速。\n"
        "触屏：底部有移动、跳跃、演奏、进门、重来、暂停和调速按钮。\n"
        "支持横竖屏、安全区、全屏和后台暂停。没有跨次游玩存档。\n"
        "字体许可证见 FONT-LICENSE.txt。\n",
        encoding="utf-8")
    entries = []
    for file in sorted(destination.iterdir()):
        if file.is_file() and file.name != "SHA256SUMS.txt":
            with file.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            entries.append(f"{digest}  {file.name}")
    (destination / "SHA256SUMS.txt").write_text("\n".join(entries) + "\n", encoding="utf-8")
    print(f"Standalone HTML: {output} ({output.stat().st_size:,} bytes)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "build/web-runtime")
    parser.add_argument("--output", type=Path, default=ROOT / "dist/Web")
    args = parser.parse_args()
    build(args.source, args.output)
