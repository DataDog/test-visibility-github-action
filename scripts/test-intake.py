#!/usr/bin/env python3
"""A stand-in for Datadog's Test Optimization intake, for the CI's Go tests.

Usage: test-intake.py <port file> <request log>

It listens on a free local port, writes that port to <port file> once it
accepts connections, and appends "<method> <path>" for every request to
<request log>. It appends the body of every test event request, gzip-decoded,
to <request log>.payloads, where scripts/test-go-reporting.sh looks for the
test's name: msgpack and JSON both keep strings as UTF-8 bytes. The settings
request gets every feature switched off, so the library only reports test
events; every other request is accepted. The caller stops it; it also stops by
itself after MAX_LIFETIME_SECONDS, so a kill that fails cannot keep a CI job
running.
"""

import gzip
import json
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from socketserver import TCPServer

MAX_LIFETIME_SECONDS = 900
SETTINGS_PATH = "/api/v2/libraries/tests/services/setting"
TEST_EVENTS_PATH = "/api/v2/citestcycle"
SETTINGS = {
    "data": {
        "id": "ci",
        "type": "ci_app_tracers_test_service_settings",
        "attributes": {
            "code_coverage": False,
            "tests_skipping": False,
            "itr_enabled": False,
            "require_git": False,
            "flaky_test_retries_enabled": False,
            "known_tests_enabled": False,
            "impacted_tests_enabled": False,
            "early_flake_detection": {"enabled": False},
            "test_management": {"enabled": False},
        },
    }
}


class Handler(BaseHTTPRequestHandler):
    def _body(self):
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            body = b""
            while True:
                size = int(self.rfile.readline().split(b";")[0], 16)
                if size == 0:
                    self.rfile.readline()
                    return body
                body += self.rfile.read(size)
                self.rfile.readline()
        return self.rfile.read(int(self.headers.get("Content-Length") or 0))

    def _record(self):
        body = self._body()
        with open(sys.argv[2], "a", encoding="utf-8") as log:
            log.write(f"{self.command} {self.path}\n")
        if self.path.startswith(TEST_EVENTS_PATH):
            if self.headers.get("Content-Encoding", "").lower() == "gzip":
                body = gzip.decompress(body)
            with open(sys.argv[2] + ".payloads", "ab") as payloads:
                payloads.write(body + b"\n")

    def _reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        self._record()
        if self.path.startswith(SETTINGS_PATH):
            self._reply(200, SETTINGS)
        else:
            self._reply(202, {})

    def do_PUT(self):
        self.do_POST()

    def do_GET(self):
        self._record()
        self._reply(200, {})

    def log_message(self, *args):
        pass


class Server(ThreadingHTTPServer):
    def server_bind(self):
        # HTTPServer.server_bind also looks the host's name up with
        # socket.getfqdn, which can stall for seconds on macOS runners;
        # nothing here uses the name.
        TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


def main():
    server = Server(("127.0.0.1", 0), Handler)
    # Renamed into place, so a reader never sees a partial port.
    with open(sys.argv[1] + ".tmp", "w", encoding="utf-8") as port_file:
        port_file.write(str(server.server_address[1]))
    os.replace(sys.argv[1] + ".tmp", sys.argv[1])
    timer = threading.Timer(MAX_LIFETIME_SECONDS, server.shutdown)
    timer.daemon = True
    timer.start()
    server.serve_forever()


if __name__ == "__main__":
    main()
