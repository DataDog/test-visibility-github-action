#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/bump-library-versions.sh [OPTIONS]

Updates one or more pinned library versions in action.yml and README.md.

Options:
  --dotnet VERSION    Datadog .NET tracer version
  --java VERSION      Datadog Java tracer version
  --js VERSION        Datadog JavaScript tracer version
  --python VERSION    Datadog Python tracer version
  --coverage VERSION  Python coverage version
  --ruby VERSION      datadog-ci Ruby gem version
  --go VERSION        Orchestrion version, including the leading v
  -h, --help          Show this help
EOF
}

updates=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --dotnet|--java|--js|--python|--coverage|--ruby|--go)
      if [[ -z "${2:-}" ]]; then
        usage >&2
        exit 1
      fi
      updates+=("${1#--}=$2")
      shift 2
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ${#updates[@]} -eq 0 ]]; then
  usage >&2
  exit 1
fi

if ! command -v ruby >/dev/null 2>&1; then
  echo "Missing required command: ruby" >&2
  exit 1
fi

ruby - "${updates[@]}" <<'RUBY'
input_names = {
  'dotnet' => 'dotnet-tracer-version',
  'java' => 'java-tracer-version',
  'js' => 'js-tracer-version',
  'python' => 'python-tracer-version',
  'coverage' => 'python-coverage-version',
  'ruby' => 'ruby-tracer-version',
  'go' => 'go-tracer-version'
}.freeze

parsed_updates = ARGV.map do |argument|
  name, version = argument.split('=', 2)
  abort "Unknown library '#{name}'" unless input_names.key?(name)
  abort "Missing version for '#{name}'" if version.nil? || version.empty?

  expected_pattern = name == 'go' ? /^v\d+\.\d+\.\d+$/ : /^\d+\.\d+\.\d+$/
  abort "Expected an exact #{name} version, got '#{version}'" unless version.match?(expected_pattern)

  [name, version]
end
updates = parsed_updates.to_h

abort 'Each library may only be specified once' unless updates.length == parsed_updates.length

action_path = 'action.yml'
readme_path = 'README.md'
action = File.read(action_path)
readme = File.read(readme_path)

updates.each do |name, version|
  input_name = input_names.fetch(name)
  action_pattern = /(^  #{Regexp.escape(input_name)}:\n(?:(?!^  [A-Za-z0-9_-]+:).*\n)*?^    default: )'[^']+'/
  abort "Unable to find #{input_name} default in #{action_path}" unless action.scan(action_pattern).length == 1
  action.sub!(action_pattern) { "#{Regexp.last_match(1)}'#{version}'" }

  readme_pattern = /^(\| #{Regexp.escape(input_name)}\s+\|[^|]*\|[^|]*\|)([^|]*)(\|)$/
  match = readme.match(readme_pattern)
  abort "Unable to find #{input_name} default in #{readme_path}" unless match

  default_cell = " #{version} "
  abort "Version '#{version}' does not fit in the README default column" if default_cell.length > match[2].length

  readme.sub!(readme_pattern) do
    "#{Regexp.last_match(1)}#{default_cell.ljust(Regexp.last_match(2).length)}#{Regexp.last_match(3)}"
  end

  puts "Updated #{input_name} to #{version}"
end

File.write(action_path, action)
File.write(readme_path, readme)
RUBY
