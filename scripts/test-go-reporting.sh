#!/usr/bin/env bash
# Runs go test in a module against a local stand-in for Datadog's intake and
# checks whether the test's event reached it.
#
# Usage: scripts/test-go-reporting.sh <module dir> <test name> reported|unreported
#
# The CI runs it in a step after the action. "reported" expects the event of
# <test name>, which go test sends when ddtest instruments it; "unreported"
# expects no such event, as when the action skipped Go. go test itself must
# pass in both cases. The event is what Test Optimization receives, so the
# check does not depend on ddtest's log messages.
set -euo pipefail

module_dir="$1"
test_name="$2"
expected="$3"
case "$expected" in
  reported|unreported) ;;
  *)
    echo "Error: Expected reported or unreported, got '$expected'." >&2
    exit 1
    ;;
esac

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Its own folder, outside the project, for every run: an earlier run's events
# must not count for this one.
intake_dir="$(mktemp -d)"

python_bin=""
for candidate in python3 python; do
  if "$candidate" -c 'import sys' >/dev/null 2>&1; then
    python_bin="$candidate"
    break
  fi
done
[ -n "$python_bin" ] || { echo "Error: The intake needs Python." >&2; exit 1; }

intake_pid=""
# Stop the intake and wait until it has exited, so its files are complete and
# free.
stop_intake() {
  if [ -n "$intake_pid" ]; then
    kill "$intake_pid" 2>/dev/null || true
    wait "$intake_pid" 2>/dev/null || true
    intake_pid=""
  fi
}
trap stop_intake EXIT

# Without the step's output streams: on Windows, a background process that
# holds them keeps the GitHub Actions step running.
(cd "$intake_dir" && exec "$python_bin" "$scripts_dir/test-intake.py" "$intake_dir/port" \
  "$intake_dir/requests.log") > "$intake_dir/intake.out" 2>&1 &
intake_pid=$!
for _ in $(seq 1 300); do
  [ -s "$intake_dir/port" ] && break
  sleep 0.1
done
if [ ! -s "$intake_dir/port" ]; then
  cat "$intake_dir/intake.out" >&2 2>/dev/null || true
  echo "Error: The intake did not start." >&2
  exit 1
fi

log="$intake_dir/go-test.log"
if ! (cd "$module_dir" && DD_CIVISIBILITY_AGENTLESS_URL="http://127.0.0.1:$(cat "$intake_dir/port")" \
  go test -count=1 -v ./...) > "$log" 2>&1; then
  cat "$log"
  echo "Error: go test failed in $module_dir." >&2
  exit 1
fi
cat "$log"
stop_intake

echo "--- requests that reached the intake:"
cat "$intake_dir/requests.log" 2>/dev/null || echo "(none)"

# The test's own event names it; a session or module event does not. The
# payloads are binary, which grep matches in the C locale.
actual=unreported
if LC_ALL=C grep -a -q "$test_name" "$intake_dir/requests.log.payloads" 2>/dev/null; then
  actual=reported
fi
if [ "$actual" != "$expected" ]; then
  echo "Error: The event of $test_name in $module_dir is $actual, expected $expected." >&2
  exit 1
fi
echo "PASS: the event of $test_name in $module_dir is $actual"
