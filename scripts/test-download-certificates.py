#!/usr/bin/env python3
"""Isolated HTTPS/RPC certificate-policy checks; no app preferences or history are touched."""
import http.server
import json
from pathlib import Path
import shutil
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
PAYLOAD = b"Arcload certificate policy\n" * 16384


class DownloadServer(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Length", str(len(PAYLOAD)))
        self.end_headers()
        try:
            self.wfile.write(PAYLOAD)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def handle(self):
        try:
            super().handle()
        except (ConnectionResetError, BrokenPipeError, ssl.SSLError):
            pass  # Expected when a client rejects the temporary certificate.

    def log_message(self, *_):
        pass


def main():
    openssl = shutil.which("openssl")
    assert openssl, "openssl is required for the isolated test certificate"
    with tempfile.TemporaryDirectory(prefix="arcload-certificate-tests-") as directory:
        root = Path(directory)
        certificate, key = root / "certificate.pem", root / "key.pem"
        config = root / "openssl.conf"
        config.write_text("[req]\nprompt=no\ndistinguished_name=dn\nx509_extensions=extensions\n"
                          "[dn]\nCN=localhost\n[extensions]\nsubjectAltName=IP:127.0.0.1,DNS:localhost\n"
                          "basicConstraints=critical,CA:TRUE\n")
        subprocess.run([openssl, "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                        "-config", str(config), "-keyout", str(key), "-out", str(certificate)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certificate, key)
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), DownloadServer)
        server.daemon_threads = True
        server.socket = context.wrap_socket(server.socket, server_side=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        process = subprocess.Popen([
            str(ROOT / "Resources/aria2-next"), "--no-conf=true", "--enable-rpc=true",
            "--rpc-listen-all=false", f"--rpc-listen-port={port}", "--check-certificate=true",
            f"--dir={root}", f"--state-dir={root / 'state'}", "--media=file", "--max-tries=1",
            "--follow-torrent=false", "--enable-dht=false", "--enable-dht6=false",
            "--bt-enable-lpd=false", "--enable-peer-exchange=false", "--stream-max-connections=1",
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

        def rpc(method, *params):
            data = json.dumps({"jsonrpc": "2.0", "id": "certificate-test", "method": "aria2." + method,
                               "params": params}).encode()
            request = urllib.request.Request(f"http://127.0.0.1:{port}/jsonrpc", data=data,
                                             headers={"Content-Type": "application/json"})
            with opener.open(request, timeout=3) as response:
                result = json.load(response)
            assert "error" not in result, result
            return result["result"]

        def wait(gid, predicate):
            deadline = time.monotonic() + 15
            while True:
                status = rpc("tellStatus", gid)
                if predicate(status):
                    return status
                assert time.monotonic() < deadline, status
                time.sleep(0.05)

        def completed(gid):
            status = wait(gid, lambda value: value["status"] in ("complete", "error"))
            assert status["status"] == "complete", status
            assert Path(status["files"][0]["path"]).read_bytes() == PAYLOAD

        try:
            deadline = time.monotonic() + 5
            while True:
                assert process.poll() is None, "engine exited before readiness"
                try:
                    version = rpc("getVersion")
                    assert version["product"] == "aria2-next" and version["version"] == "2.8.6"
                    break
                except OSError:
                    assert time.monotonic() < deadline
                    time.sleep(0.05)
            url = f"https://127.0.0.1:{server.server_port}/file.bin"
            blocked = rpc("addUri", [url], {"out": "blocked.bin"})
            failure = wait(blocked, lambda value: value["status"] == "error")
            assert any(word in failure.get("errorMessage", "").lower() for word in ("certificate", "ssl", "tls")), failure
            print("Verification enabled: untrusted self-signed HTTPS certificate rejected.")

            paused = rpc("addUri", [url], {"pause": "true", "out": "paused.bin"})
            assert rpc("getOption", paused)["check-certificate"] == "true"
            assert rpc("changeGlobalOption", {"check-certificate": "false"}) == "OK"
            assert rpc("getGlobalOption")["check-certificate"] == "false"
            assert rpc("getOption", paused)["check-certificate"] == "true"
            rpc("forceRemove", paused)
            allowed = rpc("addUri", [url], {"pause": "true", "out": "allowed.bin"})
            assert rpc("getOption", allowed)["check-certificate"] == "false"
            rpc("unpause", allowed)
            completed(allowed)
            print("Verification disabled: new task downloaded with matching checksum; existing paused task retained its policy.")

            active = rpc("addUri", [url], {"out": "active.bin", "max-download-limit": "8192"})
            wait(active, lambda value: value["status"] == "active" and int(value["completedLength"]) > 0)
            assert rpc("changeGlobalOption", {"check-certificate": "true"}) == "OK"
            assert rpc("getOption", active)["check-certificate"] == "false"
            print("Changing the default preserves existing active transfers and their original certificate policy.")
            status = rpc("tellStatus", active)
            if status["status"] in ("active", "waiting", "paused"):
                rpc("forceRemove", active)

            assert rpc("changeGlobalOption", {"check-certificate": "true"}) == "OK"
            assert rpc("getGlobalOption")["check-certificate"] == "true"
            blocked_again = rpc("addUri", [url], {"out": "blocked-again.bin"})
            wait(blocked_again, lambda value: value["status"] == "error")
            print("Verification re-enabled: subsequent HTTPS task rejects the untrusted certificate again.")

            trusted = rpc("addUri", [url], {"out": "trusted.bin", "ca-certificate": str(certificate)})
            completed(trusted)
            print("Verification enabled with explicit test CA: trusted HTTPS download succeeds with matching checksum.")
            assert rpc("forceShutdown") == "OK"
            process.wait(timeout=5)
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    main()
