#!/usr/bin/env python3
"""Exercise the action's shell step with a local installer that fails transiently."""
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import threading

action = (Path(__file__).resolve().parents[1] / "action.yml").read_text()
step = action.split("      id: run-configuration-script\n      run: |\n", 1)[1]
step = textwrap.dedent(step.split("\n      shell: bash", 1)[0])
installer = b"""#!/usr/bin/env bash
set -e
echo attempt >> "$INSTALL_ATTEMPTS"
if [ "$(wc -l < "$INSTALL_ATTEMPTS")" -le "$INSTALL_FAILURES" ]; then
  echo FAILED_ATTEMPT=true
  exit 1
fi
echo READY=true
"""

for name, download_failures, install_failures in [
    ("recovers after download and install failures", 1, 1),
    ("stops after three download failures", 3, 0),
    ("stops after three install failures", 0, 3),
]:
    class Handler(BaseHTTPRequestHandler):
        requests = 0

        def do_GET(self):
            Handler.requests += 1
            failed = Handler.requests <= download_failures
            body = b"Transient failure" if failed else installer
            self.send_response(503 if failed else 200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    with tempfile.TemporaryDirectory() as directory, ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        workspace = Path(directory)
        (workspace / "step.sh").write_text(step)
        github_env = workspace / "github-env"
        github_env.write_text("EXISTING=true\n")
        install_attempts = workspace / "install-attempts"
        env = dict(os.environ, GITHUB_WORKSPACE=directory, GITHUB_ENV=str(github_env),
                   INSTALLATION_SCRIPT_URL=f"http://127.0.0.1:{server.server_port}/installer.sh",
                   INSTALLATION_SCRIPT_CHECKSUM=hashlib.sha256(installer).hexdigest(),
                   INSTALL_ATTEMPTS=str(install_attempts), INSTALL_FAILURES=str(install_failures),
                   NO_PROXY="127.0.0.1", no_proxy="127.0.0.1")
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        try:
            result = subprocess.run(["bash", "--noprofile", "--norc", "-eo", "pipefail", "step.sh"],
                                    cwd=directory, env=env, text=True, capture_output=True, timeout=30)
        finally:
            server.shutdown()
            thread.join()
            datadog_link = Path("/github/workspace/.datadog")
            if datadog_link.is_symlink() and os.readlink(datadog_link) == str(workspace / ".datadog"):
                datadog_link.unlink()

        succeeded = download_failures < 3 and install_failures < 3
        assert (result.returncode == 0) == succeeded, result.stdout + result.stderr
        assert Handler.requests == min(download_failures + 1, 3), result.stderr
        attempts = len(install_attempts.read_text().splitlines()) if install_attempts.exists() else 0
        assert attempts == (0 if download_failures == 3 else min(install_failures + 1, 3)), result.stderr
        assert github_env.read_text() == "EXISTING=true\n" + ("READY=true\n" if succeeded else ""), result.stderr
        print(f"PASS: {name}")
