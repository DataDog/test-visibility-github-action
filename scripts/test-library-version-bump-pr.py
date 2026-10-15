#!/usr/bin/env python3
"""Check bump PR failure handling without GitHub or Git mutations."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
STUB = "#!" + sys.executable + "\n" + textwrap.dedent('''\
    import json
    import os
    from pathlib import Path
    import sys

    tool = Path(sys.argv[0]).name
    args = sys.argv[1:]
    scenario = os.environ["SCENARIO"]
    with open(os.environ["COMMAND_LOG"], "a") as log:
        log.write(json.dumps([tool, *args]) + "\\n")

    if tool == "git":
        if args[0] == "show-ref":
            sys.exit(1)
    elif tool == "curl":
        url = args[-1]
        if "maven" in url:
            print("<metadata><versioning><latest>99.0.0</latest></versioning></metadata>")
        else:
            print(json.dumps({"versions": ["99.0.0"], "version": "99.0.0",
                              "info": {"version": "99.0.0"}}))
    elif tool == "gh":
        if args[:2] == ["api", "repos/DataDog/test-visibility-github-action"]:
            if scenario == "repo_404":
                print("HTTP 404: Not Found", file=sys.stderr)
                sys.exit(1)
            print("false" if scenario == "no_write_access" else "true")
        elif args[:2] == ["api", "user"]:
            print("juan-fernandez")
        elif args[:2] == ["api", "repos/DataDog/orchestrion/releases/latest"]:
            print("v99.0.0")
        elif args[:2] == ["pr", "list"]:
            pass
        elif args[:3] == ["api", "--paginate", "repos/DataDog/test-visibility-github-action/labels"]:
            if scenario == "label_list_failure":
                sys.exit(1)
            print("semver-minor")
            if scenario not in ("missing_label", "label_create_failure"):
                print("library-version-bump")
        elif args[:2] == ["label", "create"]:
            if scenario == "label_create_failure":
                print("HTTP 404: Not Found", file=sys.stderr)
                sys.exit(1)
        elif args[:2] == ["pr", "create"]:
            body = Path(args[args.index("--body-file") + 1]).read_text()
            assert "### What does this PR do?" in body
            assert "### Describe how to test/QA your changes" in body
            assert "Go/Orchestrion:" in body
            print("https://github.com/DataDog/test-visibility-github-action/pull/123")
        else:
            raise AssertionError(args)
''')


class BumpPRTests(unittest.TestCase):
    def run_script(self, scenario, *args):
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            (workspace / "scripts").mkdir()
            for name in ("create-library-version-bump-pr.sh", "bump-library-versions.sh"):
                shutil.copy2(ROOT / "scripts" / name, workspace / "scripts" / name)
            for name in ("action.yml", "README.md"):
                shutil.copy2(ROOT / name, workspace / name)
            commands = workspace / "commands"
            commands.mkdir()
            for name in ("gh", "git", "curl"):
                stub = commands / name
                stub.write_text(STUB)
                stub.chmod(0o755)
            log = workspace / "command-log"
            env = dict(os.environ, PATH=f"{commands}:{os.environ['PATH']}",
                       SCENARIO=scenario, COMMAND_LOG=str(log))
            result = subprocess.run(["bash", "scripts/create-library-version-bump-pr.sh", *args],
                                    cwd=workspace, env=env, text=True, capture_output=True, timeout=30)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            return result, calls

    def assert_no_git_mutations(self, calls):
        mutating_commands = {"fetch", "checkout", "add", "commit", "push"}
        self.assertFalse(any(call[0] == "git" and call[1] in mutating_commands
                             for call in calls), calls)

    def test_existing_labels_are_reused(self):
        result, calls = self.run_script("existing_labels")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(any(call[:3] == ["gh", "label", "create"] for call in calls))
        self.assertIn(["git", "commit", "-S", "-m", "chore: bump pinned library versions"], calls)
        verify = calls.index(["git", "verify-commit", "HEAD"])
        push = next(i for i, call in enumerate(calls) if call[:2] == ["git", "push"])
        create = next(i for i, call in enumerate(calls) if call[:3] == ["gh", "pr", "create"])
        self.assertLess(verify, push)
        self.assertLess(push, create)
        self.assertEqual(calls[create][-4:], ["--label", "library-version-bump", "--label", "semver-minor"])

    def test_missing_label_is_created_before_branch(self):
        result, calls = self.run_script("missing_label")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        labels = [call for call in calls if call[:3] == ["gh", "label", "create"]]
        self.assertEqual(len(labels), 1)
        self.assertEqual(labels[0][3], "library-version-bump")
        self.assertNotIn("--force", labels[0])
        self.assertLess(calls.index(labels[0]), calls.index(["git", "fetch", "origin", "main"]))

    def test_wrong_account_stops_before_package_lookup(self):
        for scenario in ("repo_404", "no_write_access"):
            with self.subTest(scenario=scenario):
                result, calls = self.run_script(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("current gh account", result.stderr)
                self.assertEqual(len(calls), 1)
                self.assert_no_git_mutations(calls)

    def test_label_list_failure_stops_before_branch(self):
        result, calls = self.run_script("label_list_failure")
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_git_mutations(calls)
        self.assertFalse(any(call[:3] == ["gh", "label", "create"] for call in calls))

    def test_label_creation_failure_stops_before_branch(self):
        result, calls = self.run_script("label_create_failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No branch, commit, or push was created", result.stderr)
        self.assert_no_git_mutations(calls)
        self.assertFalse(any(call[:3] == ["gh", "pr", "create"] for call in calls))

    def test_dry_run_does_not_create_labels_or_pr(self):
        for scenario in ("missing_label", "no_write_access"):
            with self.subTest(scenario=scenario):
                result, calls = self.run_script(scenario, "--dry-run")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("Dry run only", result.stdout)
                self.assert_no_git_mutations(calls)
                self.assertFalse(any(call[:3] in (["gh", "label", "create"], ["gh", "pr", "create"])
                                     for call in calls))


if __name__ == "__main__":
    unittest.main()
