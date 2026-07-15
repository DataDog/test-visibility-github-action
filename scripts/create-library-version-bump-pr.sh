#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/create-library-version-bump-pr.sh [--dry-run]

Checks the official package sources for newer supported library releases, then
opens one PR that updates every outdated pinned default.

Options:
  --dry-run   Print the bump PR that would be created
  -h, --help  Show this help
EOF
}

dry_run=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

for command in curl gh git ruby; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

gh api user --silent >/dev/null

base_branch="main"
bump_label="library-version-bump"
remote="origin"
repo="DataDog/test-visibility-github-action"
semver_minor_label="semver-minor"
semver_patch_label="semver-patch"

read_default() {
  ruby -ryaml -e 'puts YAML.load_file("action.yml").fetch("inputs").fetch(ARGV.fetch(0)).fetch("default")' "$1"
}

current_dotnet=$(read_default dotnet-tracer-version)
current_java=$(read_default java-tracer-version)
current_js=$(read_default js-tracer-version)
current_python=$(read_default python-tracer-version)
current_coverage=$(read_default python-coverage-version)
current_ruby=$(read_default ruby-tracer-version)
current_go=$(read_default go-tracer-version)

latest_dotnet=$(
  curl -fsSL https://api.nuget.org/v3-flatcontainer/dd-trace/index.json |
    ruby -rjson -e 'versions = JSON.parse(STDIN.read).fetch("versions"); puts versions.reject { |version| version.include?("-") }.last'
)
latest_java=$(
  curl -fsSL https://repo1.maven.org/maven2/com/datadoghq/dd-java-agent/maven-metadata.xml |
    ruby -rrexml/document -e 'document = REXML::Document.new(STDIN.read); puts REXML::XPath.first(document, "/metadata/versioning/latest").text'
)
latest_js=$(
  curl -fsSL https://registry.npmjs.org/dd-trace/latest |
    ruby -rjson -e 'puts JSON.parse(STDIN.read).fetch("version")'
)
latest_python=$(
  curl -fsSL https://pypi.org/pypi/ddtrace/json |
    ruby -rjson -e 'puts JSON.parse(STDIN.read).fetch("info").fetch("version")'
)
latest_coverage=$(
  curl -fsSL https://pypi.org/pypi/coverage/json |
    ruby -rjson -e 'puts JSON.parse(STDIN.read).fetch("info").fetch("version")'
)
latest_ruby=$(
  curl -fsSL https://rubygems.org/api/v1/gems/datadog-ci.json |
    ruby -rjson -e 'puts JSON.parse(STDIN.read).fetch("version")'
)
latest_go=$(gh api repos/DataDog/orchestrion/releases/latest --jq '.tag_name')

is_exact_version() {
  [[ "$1" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

semver_parts() {
  local version="${1#v}"
  IFS=. read -r semver_major semver_minor semver_patch <<< "$version"
  echo "$semver_major $semver_minor $semver_patch"
}

version_is_newer() {
  local current_major current_minor current_patch next_major next_minor next_patch
  read -r current_major current_minor current_patch <<< "$(semver_parts "$1")"
  read -r next_major next_minor next_patch <<< "$(semver_parts "$2")"

  (( next_major > current_major ||
     (next_major == current_major && next_minor > current_minor) ||
     (next_major == current_major && next_minor == current_minor && next_patch > current_patch) ))
}

change_requires_minor_release() {
  local current_major current_minor _current_patch next_major next_minor _next_patch
  read -r current_major current_minor _current_patch <<< "$(semver_parts "$1")"
  read -r next_major next_minor _next_patch <<< "$(semver_parts "$2")"

  (( next_major > current_major || (next_major == current_major && next_minor > current_minor) ))
}

changes=()
bump_args=()
release_bump_kind="patch"

record_change() {
  local name="$1"
  local display_name="$2"
  local current="$3"
  local latest="$4"

  if ! is_exact_version "$current" || ! is_exact_version "$latest"; then
    echo "Expected exact semantic versions for $display_name, got '$current' and '$latest'" >&2
    exit 1
  fi

  if [[ "$current" == "$latest" ]]; then
    return 0
  fi

  if ! version_is_newer "$current" "$latest"; then
    echo "Refusing to downgrade $display_name from $current to $latest" >&2
    exit 1
  fi

  changes+=("$display_name: $current -> $latest")
  bump_args+=("--$name" "$latest")
  if change_requires_minor_release "$current" "$latest"; then
    release_bump_kind="minor"
  fi
}

record_change dotnet ".NET" "$current_dotnet" "$latest_dotnet"
record_change java "Java" "$current_java" "$latest_java"
record_change js "JavaScript" "$current_js" "$latest_js"
record_change python "Python" "$current_python" "$latest_python"
record_change coverage "Python coverage" "$current_coverage" "$latest_coverage"
record_change ruby "Ruby" "$current_ruby" "$latest_ruby"
record_change go "Go/Orchestrion" "$current_go" "$latest_go"

if [[ ${#changes[@]} -eq 0 ]]; then
  echo "All pinned library versions are current."
  exit 0
fi

if [[ "$release_bump_kind" == "minor" ]]; then
  release_label="$semver_minor_label"
else
  release_label="$semver_patch_label"
fi

if [[ "$dry_run" != "true" ]]; then
  existing_pr_url=$(gh pr list \
    --repo "$repo" \
    --label "$bump_label" \
    --state open \
    --json url \
    --jq '.[0].url // ""')
  if [[ -n "$existing_pr_url" ]]; then
    echo "An open bump PR already exists: $existing_pr_url"
    exit 0
  fi
fi

github_user=$(gh api user --jq '.login')
branch_name="$github_user/library-version-bump-$(date -u +%Y%m%d-%H%M%S)"

echo "Pinned library updates:"
printf '  - %s\n' "${changes[@]}"
echo "Release bump kind: $release_bump_kind"
echo "Branch to create: $branch_name"
echo "Labels to apply: $bump_label $release_label"

if [[ "$dry_run" == "true" ]]; then
  echo "Dry run only. No branch, commit, labels, push, or PR were created."
  exit 0
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree must be clean before creating a bump PR." >&2
  exit 1
fi

if git show-ref --verify --quiet "refs/heads/$branch_name"; then
  echo "Local branch '$branch_name' already exists. Delete it before rerunning the script." >&2
  exit 1
fi

git fetch "$remote" "$base_branch"
git checkout -b "$branch_name" FETCH_HEAD

scripts/bump-library-versions.sh "${bump_args[@]}"

git add action.yml README.md
git commit -S -m "chore: bump pinned library versions"
git verify-commit HEAD
git push -u "$remote" "$branch_name"

gh label create "$bump_label" \
  --repo "$repo" \
  --description "Marks PRs that bump pinned library versions" \
  --color "1D76DB" \
  --force

gh label create "$release_label" \
  --repo "$repo" \
  --description "Requests a $release_bump_kind test-visibility-github-action release after merge" \
  --color "0E8A16" \
  --force

changes_markdown=$(printf -- '- %s\n' "${changes[@]}")
body_file=$(mktemp)
trap 'rm -f "$body_file"' EXIT
cat > "$body_file" <<EOF
<!--
* New contributors are highly encouraged to read our
  [CONTRIBUTING](/CONTRIBUTING.md) documentation.
* The pull request:
  * Should only fix one issue or add one feature at a time.
  * Must update the test suite for the relevant functionality.
  * Should pass all status checks before being reviewed or merged.
* Commit titles should be prefixed with general area of pull request's change.
* Draft PRs should be prefixed with \`[WIP]\` in their title.

-->
### What does this PR do?

<!--
* A brief description of the change being made with this pull request.
* If the description here cannot be expressed in a succinct form, consider
  opening multiple pull requests instead of a single one.
-->

Updates the pinned default library versions:

$changes_markdown
### Motivation

<!--
* What inspired you to submit this pull request?
* Link any related GitHub issues or PRs here.
-->

Keep the action's tested library snapshot current without resolving new defaults during customer workflow runs.

### Additional Notes

<!--
* Anything else we should know when reviewing?
* Include benchmarking information here whenever possible.
* Include info about alternatives that were considered and why the proposed
  version was chosen.
-->

The versions were read from their official package sources by \`scripts/create-library-version-bump-pr.sh\`.

### Possible Drawbacks / Trade-offs

<!--
* What are the possible side-effects or negative impacts of the code change?
-->

Only the listed languages receive new defaults in this release.

### Describe how to test/QA your changes

<!--
* Write here in detail or link to detailed instructions on how this change can
  be tested/QAd/validated, including any environment setup.
-->

Run the existing GitHub Actions test matrix and verify that \`action.yml\` and \`README.md\` list the same defaults.
EOF

gh pr create \
  --repo "$repo" \
  --base "$base_branch" \
  --head "$branch_name" \
  --title "chore: bump pinned library versions" \
  --body-file "$body_file" \
  --label "$bump_label" \
  --label "$release_label"
