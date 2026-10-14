import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("stage_beta", Path(__file__).with_name("stage-beta-assets.py"))
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)


class StageBetaTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = dict(release_tag="v1.3.2-beta2", source_sha="a" * 40, windows_signing="unsigned-transition")
        self.env = dict(GITHUB_REF="refs/heads/master", GITHUB_EVENT_NAME="workflow_dispatch",
                        GITHUB_REPOSITORY=stage.REPO, GITHUB_RUN_ID="123",
                        RELEASE_MIRROR_BUCKET="example-downloads", RELEASE_MIRROR_BASE_URL="https://cdn.example.invalid",
                        RELEASE_MIRROR_DISTRIBUTION_ID="EDISTRIBUTION", GITHUB_STEP_SUMMARY=str(self.root / "summary"))
        self.entries = []
        for target, original, suffix in (("macos-arm64", "original.pkg.zip", ".pkg.zip"),
                                           ("windows-x64", "original.exe", ".exe")):
            data = target.encode()
            checksum = hashlib.sha256(data).hexdigest()
            name = f"KeyKey-1.3.2-beta2-{target}-{checksum}{suffix}"
            (self.root / name).write_bytes(data)
            self.entries.append(dict(target=target, original=original, name=name, sha256=checksum, size=len(data)))
        (self.root / "copies.json").write_text(json.dumps(self.entries))
        self.report = self.root / "report.json"
        self.report.write_text(json.dumps(dict(schema_version=1,
            release=dict(target="windows-x64", version="1.3.2-beta2", release_tag=self.config["release_tag"],
                         source_sha="a" * 40, tag_sha="a" * 40, windows_signing="unsigned-transition",
                         minimum_system_version="10.0.0"),
            sha256=self.entries[1]["sha256"], size=self.entries[1]["size"], verifier_run_id="123",
            verifier_source_sha="b" * 40, verification="native-windows-signing-state-and-product-version")))

    def execute(self, assets=None, upload_error=None):
        def run(args, **kwargs):
            if args[:3] == ["aws", "s3api", "put-object"]:
                if upload_error:
                    return SimpleNamespace(returncode=1, args=args, stderr=upload_error, stdout="")
                return SimpleNamespace(returncode=0, stdout=json.dumps(dict(
                    ChecksumSHA256=args[args.index("--checksum-sha256") + 1])))
            if args[:3] == ["aws", "s3api", "get-object"]:
                key = args[args.index("--key") + 1]
                path = Path(args[args.index("--checksum-mode") + 2])
                path.write_bytes((self.root / key.split("/")[-1]).read_bytes())
            return SimpleNamespace(returncode=0)
        def output(args, **kwargs):
            return json.dumps(dict(Invalidation=dict(Id="TEST"))) if args[0] == "aws" else "b" * 40
        with patch.dict(os.environ, self.env), patch.object(stage, "release", return_value=("1.3.2", dict(assets=assets or []))), \
             patch.object(stage, "packages", return_value=self.entries), patch.object(stage.subprocess, "run", side_effect=run) as calls, \
             patch.object(stage.subprocess, "check_output", side_effect=output), patch.object(stage, "verify_download") as downloads:
            stage.publish(self.config, self.root, self.report)
            return calls, downloads

    def test_adds_identical_copies_only_and_conditionally_creates_s3_keys(self):
        calls, downloads = self.execute()
        uploads = [c.args[0] for c in calls.call_args_list if c.args[0][:3] == ["gh", "release", "upload"]]
        self.assertEqual(len(uploads), 2)
        self.assertTrue(all("--clobber" not in args for args in uploads))
        puts = [c.args[0] for c in calls.call_args_list if c.args[0][:3] == ["aws", "s3api", "put-object"]]
        self.assertEqual(len(puts), 2)
        for args in puts:
            self.assertEqual(args[args.index("--if-none-match") + 1], "*")
            self.assertIn("/v1.3.2-beta2/KeyKey-", args[args.index("--key") + 1])
        self.assertEqual(downloads.call_count, 4)

    def test_existing_equal_copies_are_read_back_never_reuploaded(self):
        assets = [dict(name=e["name"], digest="sha256:" + e["sha256"], size=e["size"]) for e in self.entries]
        calls, _ = self.execute(assets, "An error occurred (PreconditionFailed) when calling PutObject")
        self.assertFalse(any(c.args[0][0] == "gh" for c in calls.call_args_list))

    def test_different_existing_copy_or_changed_local_bytes_stop_before_writes(self):
        with self.assertRaisesRegex(ValueError, "never overwrite"):
            self.execute([dict(name=self.entries[0]["name"], digest="sha256:" + "0" * 64, size=1)])
        (self.root / self.entries[1]["name"]).write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "Staged copy changed"):
            self.execute()
        self.assertFalse((self.root / "summary").exists())

    def test_access_denied_is_not_treated_as_missing_or_existing(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.execute(upload_error="An error occurred (AccessDenied) when calling PutObject")
        self.assertFalse((self.root / "summary").exists())

    def test_work_branch_pr_or_wrong_repository_cannot_publish(self):
        for field, value in (("GITHUB_REF", "refs/heads/work"), ("GITHUB_EVENT_NAME", "pull_request"),
                             ("GITHUB_REPOSITORY", "attacker/KeyKey")):
            self.env[field] = value
            with self.assertRaisesRegex(ValueError, "reviewed master"):
                self.execute()
            self.env.update(GITHUB_REF="refs/heads/master", GITHUB_EVENT_NAME="workflow_dispatch", GITHUB_REPOSITORY=stage.REPO)

    def test_native_report_must_bind_same_run_revision_and_original_bytes(self):
        for field, value in (("verifier_run_id", "old"), ("verifier_source_sha", "c" * 40),
                             ("sha256", "0" * 64), ("size", 0), ("verification", "mock")):
            original = json.loads(self.report.read_text())
            modified = dict(original, **{field: value})
            self.report.write_text(json.dumps(modified))
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "Native Windows report"):
                self.execute()
            self.report.write_text(json.dumps(original))

    def test_stable_or_changed_release_tag_cannot_be_staged(self):
        config = dict(self.config, release_tag="v1.3.2")
        with self.assertRaisesRegex(ValueError, "numbered beta"):
            stage.release(config)
        with patch.object(stage, "gh", side_effect=[dict(tagName="v1.3.2-beta2", isDraft=False, isPrerelease=True), dict(sha="c" * 40)]), \
                self.assertRaisesRegex(ValueError, "reviewed source"):
            stage.release(self.config)


if __name__ == "__main__":
    unittest.main()
