#!/usr/bin/env python3
"""Check empty/manual RPC secrets with isolated loopback engines; no app data is touched."""
import http.server
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
PAYLOAD = b"Arcload optional RPC authentication\n" * 1024


class DownloadServer(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Length", str(len(PAYLOAD)))
        self.end_headers()
        self.wfile.write(PAYLOAD)

    def log_message(self, *_):
        pass


def check(secret, origin):
    with tempfile.TemporaryDirectory(prefix="arcload-rpc-auth-") as directory:
        root = Path(directory)
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        arguments = [
            str(ROOT / "Resources/aria2-next"), "--no-conf=true", "--enable-rpc=true",
            "--rpc-listen-all=false", f"--rpc-listen-port={port}",
            f"--dir={root}", f"--state-dir={root / 'state'}", "--media=file",
            "--follow-torrent=false", "--enable-dht=false", "--enable-dht6=false",
            "--bt-enable-lpd=false", "--enable-peer-exchange=false",
        ]
        if secret:
            arguments.append(f"--rpc-secret={secret}")
        process = subprocess.Popen(arguments, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

        def response(method, params):
            body = json.dumps({"jsonrpc": "2.0", "id": "auth-test", "method": "aria2." + method,
                               "params": params}).encode()
            request = urllib.request.Request(f"http://127.0.0.1:{port}/jsonrpc", data=body,
                                             headers={"Content-Type": "application/json"})
            try:
                stream = opener.open(request, timeout=5)
            except urllib.error.HTTPError as error:
                stream = error
            with stream:
                return json.load(stream)

        def rpc(method, *params):
            prefix = ["token:" + secret] if secret else []
            result = response(method, prefix + list(params))
            assert "error" not in result, result
            return result["result"]

        try:
            deadline = time.monotonic() + 5
            while True:
                assert process.poll() is None, "engine exited before readiness"
                try:
                    version = rpc("getVersion")
                    assert version["product"] == "aria2-next" and version["version"] == "2.8.6"
                    break
                except OSError:
                    assert time.monotonic() < deadline, "RPC not ready"
                    time.sleep(0.05)
            if secret:
                assert "error" in response("getGlobalStat", [])
                assert "error" in response("getGlobalStat", ["token:incorrect-secret"])
            assert isinstance(rpc("getGlobalStat"), dict)
            assert isinstance(rpc("tellActive"), list)
            assert isinstance(rpc("tellWaiting", 0, 500), list)
            assert isinstance(rpc("tellStopped", 0, 500), list)
            assert rpc("changeGlobalOption", {"max-concurrent-downloads": "2"}) == "OK"
            gid = rpc("addUri", [origin + "/file.bin"], {"pause": "true"})
            assert isinstance(rpc("getOption", gid), dict)
            assert rpc("changeOption", gid, {"max-download-limit": "0"}) == "OK"
            assert rpc("unpause", gid) == gid
            deadline = time.monotonic() + 10
            while True:
                status = rpc("tellStatus", gid)
                if status["status"] in ("complete", "error"):
                    assert status["status"] == "complete", status
                    break
                assert time.monotonic() < deadline, status
                time.sleep(0.05)
            assert Path(status["files"][0]["path"]).read_bytes() == PAYLOAD
            assert rpc("removeDownloadResult", gid) == "OK"
            assert rpc("forceShutdown") == "OK"
            process.wait(timeout=5)
            print(f"{'Manual secret' if secret else 'Empty secret'}: RPC, task controls and download checksum passed.")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)


def main():
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), DownloadServer)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        origin = f"http://127.0.0.1:{server.server_port}"
        check("", origin)
        check("manually-entered-test-secret", origin)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
