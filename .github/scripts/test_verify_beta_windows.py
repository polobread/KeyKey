import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("beta_windows", Path(__file__).with_name("verify-beta-windows.py"))
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class BetaWindowsVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.sha = "a" * 40
        self.config = dict(release_tag="v1.3.2-beta2", source_sha=self.sha, windows_signing="unsigned-transition")
        self.name = "chichi77-KeyKey-1.3.2-windows-x64-setup.unsigned.exe"
        self.data = b"isolated fake installer, not executed"
        self.digest = hashlib.sha256(self.data).hexdigest()
        self.info = dict(platform="windows", version="1.3.2", release_tag="v1.3.2-beta2",
                         source_sha=self.sha, tag_sha=self.sha,
                         assets=[dict(name=self.name, sha256=self.digest, size=len(self.data))])
        self.release = dict(tagName="v1.3.2-beta2", isDraft=False, isPrerelease=True,
                            assets=[dict(name=self.name, digest="sha256:" + self.digest, size=len(self.data))])

    def execute(self, os_error=None):
        def output(command, **kwargs):
            return json.dumps(self.release) if command[0] == "gh" else "b" * 40

        def download(command, **kwargs):
            name = command[command.index("--pattern") + 1]
            path = Path(command[command.index("--dir") + 1]) / name
            if name.endswith("build-info.json"):
                path.write_text(json.dumps(self.info))
            elif name.endswith(".sha256"):
                path.write_text(f"{self.digest}  {self.name}\n")
            else:
                path.write_bytes(self.data)

        with patch.object(verifier.sys, "platform", "win32"), \
             patch.dict(os.environ, GITHUB_RUN_ID="123"), \
             patch.object(verifier.subprocess, "check_output", side_effect=output), \
             patch.object(verifier.subprocess, "run", side_effect=download), \
             patch.object(verifier.metadata, "verify_platform_package", side_effect=os_error) as native:
            verifier.verify(self.config, self.root / "out")
            return native

    def test_non_windows_cannot_issue_report(self):
        with patch.object(verifier.sys, "platform", "darwin"):
            with self.assertRaisesRegex(ValueError, "native Windows"):
                verifier.verify(self.config, self.root / "out")

    def test_report_is_bound_to_file_and_exact_beta_source(self):
        native = self.execute()
        entry = native.call_args.args[0]
        self.assertEqual(entry["windows_signing"], "unsigned-transition")
        self.assertEqual(entry["version"], "1.3.2-beta2")
        report = json.loads((self.root / "out/windows-x64.verified.json").read_text())
        self.assertEqual(report["sha256"], self.digest)
        self.assertEqual(report["release"]["tag_sha"], self.sha)
        self.assertEqual(report["verifier_run_id"], "123")
        self.assertEqual(report["verifier_source_sha"], "b" * 40)
        self.assertNotIn("file", report["release"])

    def test_failed_native_verification_produces_no_report(self):
        with self.assertRaisesRegex(ValueError, "invalid installer"):
            self.execute(ValueError("invalid installer"))
        self.assertFalse((self.root / "out").exists())

    def test_wrong_release_channel_or_source_is_rejected(self):
        for key, value in (("isDraft", True), ("isPrerelease", False), ("tagName", "v1.3.2-beta1")):
            original = self.release[key]
            self.release[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.execute()
            self.release[key] = original
        self.info["source_sha"] = "c" * 40
        with self.assertRaisesRegex(ValueError, "source/tag mismatch"):
            self.execute()

    def test_changed_asset_digest_is_rejected(self):
        self.release["assets"][0]["digest"] = "sha256:" + "0" * 64
        with self.assertRaisesRegex(ValueError, "asset/build-info mismatch"):
            self.execute()


if __name__ == "__main__":
    unittest.main()
