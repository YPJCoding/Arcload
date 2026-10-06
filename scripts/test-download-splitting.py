#!/usr/bin/env python3
"""Check aria2 HTTP splitting using an isolated loopback server and temporary files.
Run: python3 scripts/test-download-splitting.py [--aria2 /path/to/aria2-next]
Does not touch app preferences, history, or the user's aria2 configuration.
"""
import argparse
import hashlib
import http.server
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import urllib.request
import uuid

PAYLOAD = bytes(range(256)) * (16 * 1024 * 1024 // 256)
LOCK = threading.Lock()
ACTIVE = {}
PEAK = {}
RANGES = {}
RANGE_SIZES = {}
CONNECTIONS = {}


class RangeServer(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path
        start, end = 0, len(PAYLOAD) - 1
        header = self.headers.get("Range") if path != "/no-range.bin" else None
        if header:
            first, last = header.removeprefix("bytes=").split("-", 1)
            start = int(first)
            end = min(int(last), end) if last else end
        with LOCK:
            ACTIVE[path] = ACTIVE.get(path, 0) + 1
            PEAK[path] = max(PEAK.get(path, 0), ACTIVE[path])
            if header:
                RANGES[path] = RANGES.get(path, 0) + 1
                RANGE_SIZES.setdefault(path, []).append(end - start + 1)
        try:
            self.send_response(206 if header else 200)
            self.send_header("Content-Length", str(end - start + 1))
            if path != "/no-range.bin":
                self.send_header("Accept-Ranges", "bytes")
            if header:
                self.send_header("Content-Range", f"bytes {start}-{end}/{len(PAYLOAD)}")
            self.end_headers()
            for offset in range(start, end + 1, 65536):
                self.wfile.write(PAYLOAD[offset:min(offset + 65536, end + 1)])
                self.wfile.flush()
                if offset + 65536 <= end:
                    time.sleep(0.01)  # Leave enough time to observe concurrent range requests.
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            with LOCK:
                ACTIVE[path] -= 1

    def log_message(self, *_):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--aria2", type=Path)
    args = parser.parse_args()
    bundled = Path(__file__).resolve().parent.parent / "Resources" / "aria2-next"
    binary = args.aria2 or bundled
    if not binary.is_file():
        parser.error("aria2-next not found; supply --aria2 /path/to/aria2-next")
    with socket.socket() as reserved:
        reserved.bind(("127.0.0.1", 0))
        port = reserved.getsockname()[1]
    secret = uuid.uuid4().hex
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def rpc(method, *params):
        body = json.dumps({"jsonrpc": "2.0", "id": "split-test", "method": "aria2." + method,
                           "params": ["token:" + secret, *params]}).encode()
        request = urllib.request.Request(f"http://127.0.0.1:{port}/jsonrpc", data=body,
                                         headers={"Content-Type": "application/json"})
        with opener.open(request, timeout=3) as response:
            result = json.load(response)
        assert "error" not in result, result
        return result["result"]

    with tempfile.TemporaryDirectory(prefix="arcload-split-test-") as directory:
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), RangeServer)
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        process = None
        try:
            process = subprocess.Popen([
                str(binary.resolve()), "--no-conf=true", "--enable-rpc=true", "--rpc-listen-all=false",
                f"--rpc-listen-port={port}", f"--rpc-secret={secret}", f"--dir={directory}",
                "--enable-dht=false", "--enable-dht6=false", "--bt-enable-lpd=false",
                "--stream-max-connections=4", "--stream-max-range-size=0", "--media=file",
                f"--state-dir={directory}/state", "--max-concurrent-downloads=2",
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            deadline = time.monotonic() + 5
            while True:
                assert process.poll() is None, "aria2 exited before RPC startup"
                try:
                    rpc("getVersion")
                    break
                except OSError:
                    assert time.monotonic() < deadline, "RPC did not become ready"
                    time.sleep(0.1)
            origin = f"http://127.0.0.1:{server.server_port}"

            def download(path):
                gid = rpc("addUri", [origin + path])
                deadline = time.monotonic() + 20
                while True:
                    status = rpc("tellStatus", gid)
                    assert status["status"] != "error", status.get("errorMessage")
                    CONNECTIONS[path] = max(CONNECTIONS.get(path, 0), int(status.get("connections", "0")))
                    if status["status"] == "complete":
                        break
                    assert time.monotonic() < deadline, "download timed out"
                    time.sleep(0.1)
                data = (Path(directory) / path.removeprefix("/")).read_bytes()
                assert hashlib.sha256(data).digest() == hashlib.sha256(PAYLOAD).digest()
                return gid

            download("/parallel.bin")
            assert PEAK["/parallel.bin"] >= 2, PEAK
            assert RANGES.get("/parallel.bin", 0) >= 1, RANGES
            assert 1 < CONNECTIONS["/parallel.bin"] <= 4, CONNECTIONS
            print("Range-supported download used", CONNECTIONS["/parallel.bin"], "payload connections; file checksum matches.")
            held = rpc("addUri", [origin + "/held.bin"], {"pause": "true"})
            assert rpc("changeGlobalOption", {"stream-max-connections": "1", "stream-max-range-size": "4194304"}) == "OK"
            assert rpc("getGlobalOption")["stream-max-connections"] == "1"
            assert rpc("getGlobalOption")["stream-max-range-size"] == "4194304"
            assert rpc("getOption", held)["stream-max-connections"] == "4"
            assert rpc("getOption", held)["stream-max-range-size"] == "0"
            assert rpc("tellStatus", held)["status"] == "paused"
            serial = download("/serial.bin")
            assert rpc("getOption", serial)["stream-max-connections"] == "1"
            # A discovery request can overlap a closing HTTP handler; inspect payload worker count.
            assert CONNECTIONS["/serial.bin"] == 1, CONNECTIONS
            assert RANGE_SIZES["/serial.bin"] and max(RANGE_SIZES["/serial.bin"]) <= 4194304
            print("Native connection ceiling=1 and 4 MiB request upper bound verified; paused options unchanged.")
            assert rpc("changeGlobalOption", {"stream-max-connections": "4", "stream-max-range-size": "0"}) == "OK"
            download("/no-range.bin")
            assert process.poll() is None
            print("Non-range server download also completed with matching checksum; no process restart.")
            print("Download splitting integration passed.")
        finally:
            if process is not None and process.poll() is None:
                try:
                    rpc("forceShutdown")
                    process.wait(timeout=5)
                except (OSError, AssertionError, subprocess.TimeoutExpired):
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


if __name__ == "__main__":
    main()
