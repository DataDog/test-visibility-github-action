#!/usr/bin/env bash
# Verify actual bump behavior in a disposable copy; never call GitHub.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/dd-action-python-defaults.XXXXXX")"
trap 'rm -rf "$fixture_root"' EXIT
cp "$repo_root/action.yml" "$repo_root/README.md" "$fixture_root/"
cd "$fixture_root"
bash "$repo_root/scripts/bump-library-versions.sh" --coverage 7.16.2 --python 4.15.5
ruby -ryaml - <<'RUBY'
action = YAML.load_file('action.yml')
inputs = action.fetch('inputs')
abort 'Coverage override must have no default' if inputs.fetch('python-coverage-version').key?('default')
abort 'Tracer bump was lost' unless inputs.fetch('python-tracer-version').fetch('default') == '4.15.5'
step = action.fetch('runs').fetch('steps').find { |item| item['id'] == 'run-configuration-script' }
env = step.fetch('env')
abort 'Coverage bump was lost' unless env.fetch('DD_DEFAULT_COVERAGE_VERSION_PYTHON') == '7.16.2'
abort 'Explicit override is not forwarded' unless env.fetch('DD_SET_COVERAGE_VERSION_PYTHON') == '${{ inputs.python-coverage-version }}'
readme = File.read('README.md')
row = readme.lines.find { |line| line.start_with?('| python-coverage-version ') }
abort 'README bump was lost' unless row.include?('7.16.2') && row.include?('7.10.7')
abort 'Python 3.9 pin was removed' unless readme.include?('`7.10.7` for Python 3.9')
RUBY
# A second bump must update the same release default, never reinstate a global pin.
bash "$repo_root/scripts/bump-library-versions.sh" --coverage 7.16.3
ruby -ryaml -e 'a = YAML.load_file("action.yml"); abort if a.fetch("inputs").fetch("python-coverage-version").key?("default"); s = a.fetch("runs").fetch("steps").find { |i| i["id"] == "run-configuration-script" }; abort unless s.fetch("env").fetch("DD_DEFAULT_COVERAGE_VERSION_PYTHON") == "7.16.3"'
echo 'PASS: coverage bumps preserve interpreter selection and strict overrides'
