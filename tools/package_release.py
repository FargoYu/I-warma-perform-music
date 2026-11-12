"""Assemble an allowlisted GitHub source tree and ready-to-upload release ZIPs."""
from pathlib import Path
import hashlib
import json
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "publish"
SOURCE = OUT / "GitHub-Source"
RELEASE = OUT / "Release"
VERSION = "v1.3"
SOURCE_FILES = ["project.godot", "export_presets.cfg", "start.tscn", "main.tscn", "end.tscn",
                "default_bus_layout.tres", "README.md", ".gitignore", "THIRD_PARTY_NOTICES.txt"]
SOURCE_DIRS = ["Assets", "addons", "levels", "objects", "physics", "scripts", "platform",
               "tools", "tests", "licenses", ".github"]
BLOCKED_NAMES = {"env.json", "export_credentials.cfg", ".DS_Store", "Thumbs.db"}
BLOCKED_PARTS = {".godot", "__pycache__", "node_modules", ".git"}
BLOCKED_SUFFIXES = {".keystore", ".jks", ".pyc", ".log", ".tmp", ".bak"}


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def allowed(path):
    return (not BLOCKED_PARTS.intersection(path.parts)
            and path.name not in BLOCKED_NAMES and path.suffix.lower() not in BLOCKED_SUFFIXES)


def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def checksums(folder):
    lines = [f"{digest(p)}  {p.name}" for p in sorted(folder.iterdir())
             if p.is_file() and p.name not in {"SHA256SUMS.txt", ".gdignore"}
             and not p.name.endswith(".idsig")]
    (folder / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def archive(folder, output, prefix=""):
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for path in sorted(folder.rglob("*")):
            if path.is_file() and (prefix or path.name != ".gdignore") and not path.name.endswith(".idsig"):
                relative = path.relative_to(folder).as_posix()
                z.write(path, prefix + relative)
    with zipfile.ZipFile(output) as z:
        if z.testzip() is not None:
            raise RuntimeError(f"Archive checksum failure: {output}")
        assert all(not n.startswith("/") and ".." not in Path(n).parts for n in z.namelist())
    print(f"Created {output.name}: {output.stat().st_size / 1024 / 1024:.1f} MiB", flush=True)


def main():
    for platform, name in [("Windows", "Warma.exe"), ("Android", "Warma.apk"), ("Web", "index.html")]:
        if not (ROOT / "dist" / platform / name).is_file():
            raise SystemExit(f"Build dist/{platform}/{name} before packaging.")
    html = (ROOT / "dist/Web/index.html").read_text(encoding="utf-8")
    if 'id="embedded-index.wasm"' not in html or 'src="index.js"' in html:
        raise SystemExit("Web output must be the standalone HTML, not a raw Godot export.")
    OUT.mkdir(exist_ok=True)
    (OUT / ".gdignore").touch()
    RELEASE.mkdir(exist_ok=True)
    if SOURCE.exists():
        # Only replace the staging directory this script owns, never a junction
        # or a computed path outside the explicit publish directory.
        resolved = SOURCE.resolve()
        if SOURCE.is_symlink() or resolved.parent != OUT.resolve() or resolved.name != "GitHub-Source":
            raise RuntimeError("Unexpected source staging path; refusing cleanup")
        shutil.rmtree(resolved)
    SOURCE.mkdir()
    for name in SOURCE_FILES:
        copy(ROOT / name, SOURCE / name)
    for name in SOURCE_DIRS:
        for path in (ROOT / name).rglob("*"):
            relative = path.relative_to(ROOT)
            if path.is_file() and allowed(relative):
                copy(path, SOURCE / relative)
    copy(ROOT / "platform/github-pages-README.txt", SOURCE / "GITHUB-PAGES.txt")

    # Publish exactly the same single HTML that works from the local filesystem.
    docs = ROOT / "docs"
    docs.mkdir(exist_ok=True)
    (docs / ".nojekyll").touch()
    (docs / ".gdignore").touch()
    for folder_name in ("Windows", "Android", "Web"):
        folder = ROOT / "dist" / folder_name
        for notice in (ROOT / "licenses").glob("*.txt"):
            copy(notice, folder / notice.name)
        copy(ROOT / "THIRD_PARTY_NOTICES.txt", folder / "THIRD_PARTY_NOTICES.txt")
        checksums(folder)
    for path in (ROOT / "dist/Web").iterdir():
        if path.is_file() and path.suffix in {".html", ".txt"}:
            copy(path, docs / path.name)
            copy(path, SOURCE / "docs" / path.name)
    for name in (".nojekyll", ".gdignore"):
        copy(docs / name, SOURCE / "docs" / name)

    manifest = []
    for path in sorted(SOURCE.rglob("*")):
        if path.is_file():
            relative = path.relative_to(SOURCE)
            if not allowed(relative):
                raise RuntimeError(f"Disallowed source file: {relative}")
            if path.stat().st_size >= 100 * 1024 * 1024:
                raise RuntimeError(f"File exceeds normal GitHub Git limit: {relative}")
            manifest.append({"path": relative.as_posix(), "bytes": path.stat().st_size, "sha256": digest(path)})
    (SOURCE / "SOURCE-MANIFEST.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    archive(SOURCE, OUT / f"Warma-{VERSION}-Source.zip", f"Warma-{VERSION}-Source/")
    for folder, name in [("Windows", "Windows-x86_64"), ("Android", "Android"), ("Web", "Web")]:
        archive(ROOT / "dist" / folder, RELEASE / f"Warma-{VERSION}-{name}.zip")
    checksums(RELEASE)
    (OUT / "发布说明.txt").write_text(
        "源码：Warma-v1.3-Source.zip。解压后，将内部工程文件上传到GitHub仓库。\n"
        "也可直接用GitHub-Source文件夹；不要把ZIP文件本身当成网站源码提交。\n"
        "网页：源码docs/index.html和Web Release内的index.html是同一个单文件游戏。\n"
        "本地可双击，GitHub Pages可直接托管；没有CMD或运行时下载依赖。\n"
        "Pages启用步骤见GitHub-Source/GITHUB-PAGES.txt。\n"
        "Release：将Release文件夹中的三个ZIP与SHA256SUMS.txt上传到GitHub Releases。\n"
        "Windows与Android保留已验收的v1.3游戏程序；新增随包第三方许可证。\n"
        "源码和Release中均不包含构建缓存、SDK、签名私钥、本机配置或旧版本EXE。\n",
        encoding="utf-8")
    checksums(OUT)
    print(f"Source: {len(manifest)} allowlisted files. Package folder: {OUT}", flush=True)


if __name__ == "__main__":
    main()
