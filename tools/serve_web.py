"""Optional HTTP hosting test server; the release HTML also runs without it."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import threading
import webbrowser

parser = argparse.ArgumentParser(description="Preview the exported Warma web game")
parser.add_argument("--port", type=int, default=8060)
parser.add_argument("--no-browser", action="store_true")
parser.add_argument("--directory", type=Path, default=Path(__file__).resolve().parents[1] / "dist/Web")
args = parser.parse_args()

class Handler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm", ".pck": "application/octet-stream", ".js": "text/javascript"}

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

server = ThreadingHTTPServer(("127.0.0.1", args.port), partial(Handler, directory=str(args.directory.resolve())))
url = f"http://127.0.0.1:{args.port}/"
print(f"Warma web preview: {url}\nKeep this window open. Ctrl+C stops the server.", flush=True)
if not args.no_browser:
    threading.Timer(0.5, lambda: webbrowser.open(url)).start()
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
finally:
    server.server_close()
