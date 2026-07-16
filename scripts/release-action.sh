#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/release-action.sh [--tag vX.Y.Z] [--sha COMMIT] [--dry-run] [--allow-version-mismatch]

Creates an action release from a signed commit on main. By default, the script
derives the next immutable action tag from merged PR labels since the previous
immutable tag. It atomically pushes that tag and the moving major branch; the
existing release workflow then creates the GitHub Release.

Options:
  --tag TAG       Immutable action tag to create, e.g. v3.0.0
  --sha COMMIT    Commit to release; defaults to origin/main after fetch
  --dry-run       Print the release without creating or pushing refs
  --allow-version-mismatch
                  Allow --tag to be lower than the release labels imply
  -h, --help      Show this help
EOF
}

dry_run=false
requested_tag=""
requested_sha=""
allow_version_mismatch=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --tag)
      if [[ -n "$requested_tag" || -z "${2:-}" ]]; then
        usage >&2
        exit 1
      fi
      requested_tag="$2"
      shift 2
      ;;
    --sha)
      if [[ -n "$requested_sha" || -z "${2:-}" ]]; then
        usage >&2
        exit 1
      fi
      requested_sha="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    --allow-version-mismatch)
      allow_version_mismatch=true
      shift
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "$requested_tag" && ! "$requested_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Expected --tag to be an immutable action tag like v3.0.0, got '$requested_tag'" >&2
  exit 1
fi

if [[ "$allow_version_mismatch" == "true" && -z "$requested_tag" ]]; then
  echo "--allow-version-mismatch only applies when --tag is set." >&2
  exit 1
fi

for command in gh git; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree must be clean before creating a release." >&2
  exit 1
fi

gh api user --silent >/dev/null

base_branch="main"
remote="origin"
repo="DataDog/test-visibility-github-action"
pr_limit=200
major_label="semver-major"
minor_label="semver-minor"
patch_label="semver-patch"

git fetch --tags "$remote"
git fetch "$remote" "$base_branch"
base_ref="refs/remotes/$remote/$base_branch"

latest_tag=$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n 1)
if [[ -z "$latest_tag" ]]; then
  echo "No existing immutable action release tag found." >&2
  exit 1
fi

if ! git merge-base --is-ancestor "$latest_tag" "$base_ref"; then
  echo "Latest immutable action tag $latest_tag is not in $remote/$base_branch history." >&2
  exit 1
fi

target_sha="${requested_sha:-$base_ref}"
target_sha=$(git rev-parse "$target_sha")

if ! git cat-file -e "${target_sha}^{commit}" 2>/dev/null; then
  echo "Commit '$target_sha' was not found locally." >&2
  exit 1
fi

if ! git merge-base --is-ancestor "$target_sha" "$base_ref"; then
  echo "Commit '$target_sha' is not in $remote/$base_branch history." >&2
  exit 1
fi

if git merge-base --is-ancestor "$target_sha" "$latest_tag"; then
  echo "No unreleased commits found after $latest_tag."
  exit 0
fi

if ! git merge-base --is-ancestor "$latest_tag" "$target_sha"; then
  echo "Commit '$target_sha' is not after latest action release $latest_tag." >&2
  exit 1
fi

commit_verified=$(gh api "repos/$repo/commits/$target_sha" --jq '.commit.verification.verified')
if [[ "$commit_verified" != "true" ]]; then
  echo "Release commit '$target_sha' does not have a signature verified by GitHub." >&2
  exit 1
fi

semver_parts() {
  local version="${1#v}"
  IFS=. read -r semver_major semver_minor semver_patch <<< "$version"
  echo "$semver_major $semver_minor $semver_patch"
}

bump_rank() {
  case "$1" in
    patch) echo 1 ;;
    minor) echo 2 ;;
    major) echo 3 ;;
    *)
      echo "Unknown bump kind '$1'" >&2
      return 1
      ;;
  esac
}

tag_bump_kind() {
  local previous="$1"
  local next="$2"
  local previous_major previous_minor previous_patch next_major next_minor next_patch

  read -r previous_major previous_minor previous_patch <<< "$(semver_parts "$previous")"
  read -r next_major next_minor next_patch <<< "$(semver_parts "$next")"

  if (( next_major > previous_major )); then
    echo "major"
  elif (( next_major == previous_major && next_minor > previous_minor )); then
    echo "minor"
  elif (( next_major == previous_major && next_minor == previous_minor && next_patch > previous_patch )); then
    echo "patch"
  else
    return 1
  fi
}

next_tag_for_bump_kind() {
  local bump_kind="$1"
  local latest_major latest_minor latest_patch

  read -r latest_major latest_minor latest_patch <<< "$(semver_parts "$latest_tag")"

  case "$bump_kind" in
    major)
      echo "v$((latest_major + 1)).0.0"
      ;;
    minor)
      echo "v${latest_major}.$((latest_minor + 1)).0"
      ;;
    patch)
      echo "v${latest_major}.${latest_minor}.$((latest_patch + 1))"
      ;;
    *)
      echo "Automatic releases support '$major_label', '$minor_label', and '$patch_label'." >&2
      return 1
      ;;
  esac
}

release_bump_kind=""
release_pr_numbers=()

while IFS=$'\t' read -r pr_number merge_sha labels_csv; do
  [[ -z "$pr_number" || -z "$merge_sha" ]] && continue

  if ! git cat-file -e "${merge_sha}^{commit}" 2>/dev/null; then
    continue
  fi
  if ! git merge-base --is-ancestor "$merge_sha" "$target_sha"; then
    continue
  fi
  if git merge-base --is-ancestor "$merge_sha" "$latest_tag"; then
    continue
  fi

  pr_bump_kind=""
  IFS=, read -ra labels <<< "$labels_csv"
  for label in "${labels[@]}"; do
    case "$label" in
      "$major_label")
        pr_bump_kind="major"
        ;;
      "$minor_label")
        if [[ "$pr_bump_kind" != "major" ]]; then
          pr_bump_kind="minor"
        fi
        ;;
      "$patch_label")
        if [[ -z "$pr_bump_kind" ]]; then
          pr_bump_kind="patch"
        fi
        ;;
    esac
  done

  if [[ -z "$pr_bump_kind" ]]; then
    continue
  fi

  release_pr_numbers+=("#$pr_number")
  if [[ -z "$release_bump_kind" || "$(bump_rank "$pr_bump_kind")" -gt "$(bump_rank "$release_bump_kind")" ]]; then
    release_bump_kind="$pr_bump_kind"
  fi
done < <(
  gh pr list \
    --repo "$repo" \
    --state merged \
    --base "$base_branch" \
    --limit "$pr_limit" \
    --json number,mergedAt,mergeCommit,labels \
    --jq 'sort_by(.mergedAt) | .[] | [.number, (.mergeCommit.oid // ""), ([.labels[].name] | join(","))] | @tsv'
)

if [[ -z "$release_bump_kind" && -z "$requested_tag" ]]; then
  echo "No unreleased merged PRs with '$major_label', '$minor_label', or '$patch_label' found between $latest_tag and $target_sha."
  exit 0
fi

if [[ -z "$requested_tag" ]]; then
  next_tag=$(next_tag_for_bump_kind "$release_bump_kind")
else
  if ! requested_bump_kind=$(tag_bump_kind "$latest_tag" "$requested_tag"); then
    echo "Requested tag '$requested_tag' must be newer than latest immutable action release '$latest_tag'." >&2
    exit 1
  fi

  if [[ -n "$release_bump_kind" && "$(bump_rank "$requested_bump_kind")" -lt "$(bump_rank "$release_bump_kind")" ]]; then
    mismatch_message="Requested tag '$requested_tag' is a $requested_bump_kind release, but merged PR labels require a $release_bump_kind release."
    if [[ "$allow_version_mismatch" != "true" ]]; then
      echo "$mismatch_message" >&2
      echo "Rerun with --allow-version-mismatch to publish this tag anyway." >&2
      exit 1
    fi
    echo "Warning: $mismatch_message" >&2
  fi

  next_tag="$requested_tag"
fi

read -r next_major _next_minor _next_patch <<< "$(semver_parts "$next_tag")"
major_branch="v${next_major}"

if git rev-parse --verify --quiet "refs/tags/$next_tag" >/dev/null; then
  echo "Tag '$next_tag' already exists locally." >&2
  exit 1
fi

if gh release view "$next_tag" --repo "$repo" >/dev/null 2>&1; then
  echo "GitHub Release '$next_tag' already exists." >&2
  exit 1
fi

if git ls-remote --exit-code --heads "$remote" "$major_branch" >/dev/null 2>&1; then
  git fetch "$remote" "$major_branch"
  major_branch_sha=$(git rev-parse FETCH_HEAD)
  if ! git merge-base --is-ancestor "$major_branch_sha" "$target_sha"; then
    echo "Moving branch '$major_branch' cannot be fast-forwarded to '$target_sha'." >&2
    exit 1
  fi
fi

echo "Latest action release tag: $latest_tag"
echo "Next action release tag: $next_tag"
if [[ -n "$release_bump_kind" ]]; then
  echo "Inferred release bump kind: $release_bump_kind"
  echo "Release PRs: ${release_pr_numbers[*]}"
fi
if [[ -n "$requested_tag" ]]; then
  echo "Requested action release tag: $requested_tag"
fi
echo "Moving major branch: $major_branch"
echo "Release commit: $target_sha"

if [[ "$dry_run" == "true" ]]; then
  echo "Dry run only. No tag or branch was pushed."
  exit 0
fi

git tag -a "$next_tag" "$target_sha" -m "Release $next_tag"
git push --atomic "$remote" "refs/tags/$next_tag" "$target_sha:refs/heads/$major_branch"

echo "Pushed $next_tag and $major_branch. The release workflow will create the GitHub Release."
