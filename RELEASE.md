# Release Process

This repository ships a composite GitHub Action. Releases use immutable semantic-version tags such as `v3.0.0` and a moving major branch such as `v3`.

## Requirements

The local release scripts require `curl`, `git`, `gh`, and Ruby. Authenticate the GitHub CLI before using them:

```bash
gh auth login
gh auth status
```

The scripts that create commits use signed commits and verify the signature before pushing. Run the bump and release helpers from a clean working tree.

## Release labels

Every PR intended for a release must have one of these labels:

- `semver-patch`: requests the next patch release
- `semver-minor`: requests the next minor release
- `semver-major`: requests the next major release

If a release includes multiple merged PRs, the highest requested version change wins. A major release can also be selected explicitly by passing `--tag vX.0.0` to the release script.

## Bump pinned library versions

Use `scripts/create-library-version-bump-pr.sh` for the normal maintainer workflow. It discovers available updates and handles the complete branch, signed commit, push, and PR flow.

Preview all currently available library updates:

```bash
scripts/create-library-version-bump-pr.sh --dry-run
```

Create a single PR containing every available update:

```bash
scripts/create-library-version-bump-pr.sh
```

The script reads the official package sources for .NET, Java, JavaScript, Python, Python coverage, Ruby, and Go/Orchestrion. If at least one pinned default is outdated, it creates a branch, updates `action.yml` and `README.md`, creates and verifies a signed commit, pushes the branch, and opens a PR.

The PR receives:

- `library-version-bump`
- `semver-patch` when every update is a patch
- `semver-minor` when at least one library changes its major or minor version

Use `scripts/bump-library-versions.sh` only as a lower-level manual tool when you already know the exact versions to apply, such as for a targeted update or when testing the file changes. It only updates `action.yml` and `README.md`; it does not query package sources, create a branch or commit, push, or open a PR.

```bash
scripts/bump-library-versions.sh --java 1.65.0 --js 6.3.1
scripts/bump-library-versions.sh --go v1.12.0
```

Review and merge the resulting changes normally.

## Release the action

Preview the next release first:

```bash
scripts/release-action.sh --dry-run
```

The script fetches `main` and tags, finds merged PRs since the latest immutable action tag, reads their `semver-patch`, `semver-minor`, and `semver-major` labels, and chooses the next action tag. It requires GitHub to report the release commit's signature as verified, then atomically pushes the immutable tag and moving major branch. The existing release workflow creates the GitHub Release with generated notes.

Publish the inferred release:

```bash
scripts/release-action.sh
```

Release a specific commit on `main`:

```bash
scripts/release-action.sh --sha abc1234 --dry-run
scripts/release-action.sh --sha abc1234
```

Choose the tag manually:

```bash
scripts/release-action.sh --tag v3.0.0 --dry-run
scripts/release-action.sh --tag v3.0.0
```

If the requested tag is lower than the merged PR labels imply, the script fails. To publish that tag intentionally:

```bash
scripts/release-action.sh --tag v3.0.1 --allow-version-mismatch
```
