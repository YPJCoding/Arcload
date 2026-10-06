#!/usr/bin/env python3
"""Isolated pinned-engine checks: session/state resume, safe re-download and RPC failure.
Run: python3 scripts/test-aria2-next-lifecycle.py
Uses the range server from test-download-splitting.py; no app data is touched.
"""
import importlib.util
import json
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import uuid

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("range_fixture", Path(__file__).with_name("test-download-splitting.py"))
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class Server(fixture.RangeServer):
    def do_GET(self):
        if self.path == "/missing.bin":
            self.send_error(404)
        else:
            super().do_GET()


def main():
    with tempfile.TemporaryDirectory(prefix="arcload-next-lifecycle-") as directory:
        root = Path(directory)
        session = root / "session"
        session.write_text("")
        server = fixture.http.server.ThreadingHTTPServer(("127.0.0.1", 0), Server)
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            port = s.getsockname()[1]
        secret = uuid.uuid4().hex
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        process = None

        def rpc(method, *params):
            data = json.dumps({"jsonrpc": "2.0", "id": "lifecycle", "method": "aria2." + method,
                               "params": ["token:" + secret, *params]}).encode()
            request = urllib.request.Request(f"http://127.0.0.1:{port}/jsonrpc", data=data,
                                             headers={"Content-Type": "application/json"})
            with opener.open(request, timeout=3) as r:
                response = json.load(r)
            assert "error" not in response, response
            return response["result"]

        def start():
            nonlocal process
            shutil.copyfile(session, root / "session.input")
            process = subprocess.Popen([
                str(ROOT / "Resources/aria2-next"), "--no-conf=true", "--enable-rpc=true",
                "--rpc-listen-all=false", f"--rpc-listen-port={port}", f"--rpc-secret={secret}",
                f"--dir={root}", f"--state-dir={root / 'state'}", "--check-certificate=true",
                "--continue=false", "--allow-overwrite=false", "--auto-file-renaming=true",
                "--media=file", "--follow-metalink=false", "--follow-torrent=false",
                "--enable-dht=false", "--enable-dht6=false", "--bt-enable-lpd=false",
                "--enable-peer-exchange=false", "--stream-max-connections=1", "--stream-max-range-size=4M",
                "--max-concurrent-downloads=1", "--max-download-limit=0", "--max-overall-download-limit=0",
                f"--save-session={session}", "--save-session-interval=5", f"--input-file={root / 'session.input'}",
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            deadline = time.monotonic() + 5
            while True:
                assert process.poll() is None, "engine exited at startup"
                try:
                    version = rpc("getVersion")
                    assert version["product"] == "aria2-next" and version["version"] == "2.8.6"
                    return
                except OSError:
                    assert time.monotonic() < deadline
                    time.sleep(0.05)

        def wait_status(gid, predicate, timeout=20):
            deadline = time.monotonic() + timeout
            while True:
                status = rpc("tellStatus", gid)
                if predicate(status):
                    return status
                assert time.monotonic() < deadline, status
                time.sleep(0.05)

        def stop():
            assert rpc("saveSession") == "OK"
            assert rpc("forceShutdown") == "OK"
            process.wait(timeout=5)

        try:
            start()
            origin = f"http://127.0.0.1:{server.server_port}"
            gid = rpc("addUri", [origin + "/resume.bin"], {"max-download-limit": "524288"})
            wait_status(gid, lambda s: int(s["completedLength"]) >= 131072)
            assert rpc("pause", gid) == gid
            paused = wait_status(gid, lambda s: s["status"] == "paused")
            completed = int(paused["completedLength"])
            assert 0 < completed < len(fixture.PAYLOAD)
            stop()
            start()
            restored = wait_status(gid, lambda s: s["status"] == "paused")
            assert int(restored["completedLength"]) >= completed, (restored, completed)
            assert rpc("changeOption", gid, {"max-download-limit": "0"}) == "OK"
            assert rpc("unpause", gid) == gid
            status = wait_status(gid, lambda s: s["status"] in ("complete", "error"))
            assert status["status"] == "complete", status
            original = Path(status["files"][0]["path"])
            assert original.read_bytes() == fixture.PAYLOAD
            print("Partial progress survived pause, force shutdown and restart with the same GID; checksum matches.")

            duplicate = rpc("addUri", [origin + "/resume.bin"], {
                "out": original.name, "continue": "false", "allow-overwrite": "false", "auto-file-renaming": "true",
            })
            status = wait_status(duplicate, lambda s: s["status"] in ("complete", "error"))
            assert status["status"] == "complete", status
            renamed = Path(status["files"][0]["path"])
            assert renamed != original and renamed.read_bytes() == fixture.PAYLOAD
            assert original.read_bytes() == fixture.PAYLOAD
            assert rpc("tellStatus", gid)["status"] == "complete"
            print("Re-download produced", renamed.name, "without modifying the original file or task.")

            (root / "unrelated.bin").write_bytes(b"keep this original")
            conflicting = rpc("addUri", [origin + "/payload.bin"], {"out": "unrelated.bin"})
            status = wait_status(conflicting, lambda s: s["status"] in ("complete", "error"))
            assert status["status"] == "complete", status
            assert Path(status["files"][0]["path"]).read_bytes() == fixture.PAYLOAD
            assert (root / "unrelated.bin").read_bytes() == b"keep this original"
            print("Unrelated existing file was preserved with global continue=false / no-overwrite.")

            failed = rpc("addUri", [origin + "/missing.bin"], {"max-tries": "1"})
            wait_status(failed, lambda s: s["status"] == "error")
            assert rpc("removeDownloadResult", failed) == "OK"
            stop()
            print("Failure/removal RPC and clean shutdown passed; lifecycle integration passed.")
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
