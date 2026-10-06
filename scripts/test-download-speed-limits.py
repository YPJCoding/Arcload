#!/usr/bin/env python3
"""Isolated aria2 speed-limit integration check; no app preferences/history are touched.

Run: python3 scripts/test-download-speed-limits.py [--aria2 /path/to/aria2-next]
Uses a loopback HTTP server, an ephemeral RPC port, and temporary downloads.
"""

import argparse
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


class FileServer(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path not in ("/first.bin", "/second.bin", "/paused.bin"):
            self.send_error(404)
            return
        block = b"x" * 65536
        self.send_response(200)
        self.send_header("Content-Length", str(len(block) * 512))
        self.send_header("Connection", "close")
        self.end_headers()
        try:
            for _ in range(512):
                self.wfile.write(block)
        except (BrokenPipeError, ConnectionResetError):
            pass

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
        rpc_port = reserved.getsockname()[1]
    secret = uuid.uuid4().hex
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def rpc(method, *params):
        body = json.dumps({
            "jsonrpc": "2.0", "id": "speed-test", "method": "aria2." + method,
            "params": ["token:" + secret, *params],
        }).encode()
        request = urllib.request.Request(
            f"http://127.0.0.1:{rpc_port}/jsonrpc", data=body,
            headers={"Content-Type": "application/json"},
        )
        with opener.open(request, timeout=3) as response:
            result = json.load(response)
        assert "error" not in result, result
        return result["result"]

    with tempfile.TemporaryDirectory(prefix="arcload-speed-test-") as directory:
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FileServer)
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        process = None
        try:
            per_task_limit = 128 * 1024
            process = subprocess.Popen([
                str(binary.resolve()), "--no-conf=true", "--enable-rpc=true",
                "--rpc-listen-all=false", f"--rpc-listen-port={rpc_port}",
                f"--rpc-secret={secret}", f"--dir={directory}",
                "--enable-dht=false", "--enable-dht6=false", "--bt-enable-lpd=false",
                "--max-concurrent-downloads=2", "--stream-max-connections=1", "--media=file",
                f"--state-dir={directory}/state",
                f"--max-download-limit={per_task_limit}", "--max-overall-download-limit=0",
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

            options = rpc("getGlobalOption")
            assert options["max-download-limit"] == str(per_task_limit)
            assert options["max-overall-download-limit"] == "0"
            origin = f"http://127.0.0.1:{server.server_port}"
            gids = [rpc("addUri", [origin + path]) for path in ("/first.bin", "/second.bin")]
            paused = rpc("addUri", [origin + "/paused.bin"], {"pause": "true"})
            assert rpc("tellStatus", paused)["status"] == "paused"
            assert rpc("changeOption", paused, {"max-download-limit": "65536"}) == "OK"
            assert rpc("getOption", paused)["max-download-limit"] == "65536"

            def completed():
                return [int(rpc("tellStatus", gid)["completedLength"]) for gid in gids]

            def measure(seconds=6):
                start = completed()
                before = time.monotonic()
                time.sleep(seconds)
                end = completed()
                elapsed = time.monotonic() - before
                return [(right - left) / elapsed for left, right in zip(start, end)]

            time.sleep(2)  # Ignore initial transfer bursts.
            per_speeds = measure()
            assert all(per_task_limit * 0.4 < speed < per_task_limit * 1.8 for speed in per_speeds), per_speeds
            print("Per-task capped speeds (KiB/s):", [round(s / 1024, 1) for s in per_speeds])

            assert rpc("changeGlobalOption", {"max-overall-download-limit": str(per_task_limit)}) == "OK"
            assert rpc("getGlobalOption")["max-overall-download-limit"] == str(per_task_limit)
            assert all(rpc("getOption", gid)["max-download-limit"] == str(per_task_limit) for gid in gids)
            assert rpc("getOption", paused)["max-download-limit"] == "65536"
            time.sleep(2)
            overall_speed = sum(measure())
            assert per_task_limit * 0.4 < overall_speed < per_task_limit * 1.8, overall_speed
            assert overall_speed < sum(per_speeds) * 0.85, (overall_speed, per_speeds)
            print("Overall capped speed (KiB/s):", round(overall_speed / 1024, 1))

            assert rpc("changeGlobalOption", {"max-overall-download-limit": "0"}) == "OK"
            time.sleep(2)
            assert rpc("getGlobalOption")["max-overall-download-limit"] == "0"
            restored_speed = sum(measure())
            # Allow a bounded settling interval after changing a live throttle.
            for _ in range(3):
                if restored_speed > overall_speed * 1.3:
                    break
                restored_speed = sum(measure())
            assert restored_speed > overall_speed * 1.3, (restored_speed, overall_speed)
            print("Overall cap removed, per-task caps retained (KiB/s):", round(restored_speed / 1024, 1))

            assert rpc("changeGlobalOption", {"max-download-limit": "0"}) == "OK"
            for gid in [*gids, paused]:
                assert rpc("changeOption", gid, {"max-download-limit": "0"}) == "OK"
                assert rpc("getOption", gid)["max-download-limit"] == "0"
            unlimited_speed = sum(measure(2))
            assert unlimited_speed > per_task_limit * 4, unlimited_speed
            assert process.poll() is None, "Updating limits must not restart the process"
            print("Both caps removed (KiB/s):", round(unlimited_speed / 1024, 1))
            print("Speed-limit integration passed; active/paused options updated without a restart.")
        finally:
            if process is not None:
                if process.poll() is None:
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
                else:
                    process.wait()
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


if __name__ == "__main__":
    main()
