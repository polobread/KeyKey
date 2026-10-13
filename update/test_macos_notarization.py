import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("macos_notarization", ROOT / "update/notarize-macos.py")
notary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notary)
ID = "b9481006-8a2a-44b2-a1de-4fcc6435a524"


class NotarizationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.package = self.root / "test.pkg"
        self.package.write_bytes(b"not a real package; never submitted")
        self.commands = []

    def fake_run(self, status="Accepted", submit_exit=0, log_exit=0, stdout=None, staple_exit=0):
        def run(command, **kwargs):
            self.commands.append(command)
            if command[1:3] == ["notarytool", "submit"]:
                return subprocess.CompletedProcess(command, submit_exit,
                    stdout if stdout is not None else json.dumps(dict(id=ID, status=status)).encode(),
                    b"submission diagnostics")
            if command[1:3] == ["notarytool", "log"]:
                if not log_exit:
                    Path(command[4]).write_text(json.dumps(dict(jobId=ID, status=status,
                        issues=[dict(message="debug entitlement", path="helper")] if status == "Invalid" else [])))
                return subprocess.CompletedProcess(command, log_exit, b"log output", b"log diagnostics")
            if command[1:3] == ["stapler", "staple"] and staple_exit:
                raise subprocess.CalledProcessError(staple_exit, command)
            return subprocess.CompletedProcess(command, 0)
        return run

    def attempt(self, **kwargs):
        with patch.object(notary.subprocess, "run", side_effect=self.fake_run(**kwargs)):
            return notary.notarize(self.package, "test-profile", self.root / "logs")

    def assert_no_staple(self):
        self.assertFalse(any(command[1] == "stapler" for command in self.commands))

    def test_accepted_is_the_only_path_to_staple_then_validate(self):
        attempt = self.attempt()
        self.assertEqual([command[2] for command in self.commands], ["submit", "log", "staple", "validate"])
        self.assertEqual(json.loads((attempt / "submit.json").read_text())["status"], "Accepted")
        self.assertTrue((attempt / "notary-log.json").is_file())
        self.assertEqual((attempt / "submit.stderr.txt").read_bytes(), b"submission diagnostics")
        self.assertIn("json", self.commands[0])
        self.assertIn("--wait", self.commands[0])
        self.assertIn("--timeout", self.commands[0])
        self.assertNotIn("--password", self.commands[0])

    def test_rejected_submission_saves_detailed_log_and_never_staples(self):
        with self.assertRaisesRegex(ValueError, "not Accepted"):
            self.attempt(status="Invalid")
        self.assert_no_staple()
        report = next((self.root / "logs").glob("*/notary-log.json"))
        self.assertEqual(json.loads(report.read_text())["issues"][0]["message"], "debug entitlement")

    def test_nonzero_submit_exit_still_downloads_rejection_details(self):
        with self.assertRaisesRegex(ValueError, "exit=1"):
            self.attempt(status="Invalid", submit_exit=1)
        self.assertEqual([command[2] for command in self.commands], ["submit", "log"])
        self.assert_no_staple()

    def test_timeout_unknown_and_missing_status_never_staple(self):
        for status in ("In Progress", "Rejected", None, "accepted"):
            with self.subTest(status=status):
                self.commands.clear()
                with self.assertRaisesRegex(ValueError, "not Accepted"):
                    self.attempt(status=status)
                self.assert_no_staple()

    def test_accepted_with_nonzero_exit_is_not_success(self):
        with self.assertRaisesRegex(ValueError, "not Accepted"):
            self.attempt(submit_exit=1)
        self.assert_no_staple()

    def test_bad_response_or_id_saves_raw_diagnostics_without_staple(self):
        for response in (b"", b"not json", b"[]", b'{"status":"Accepted"}',
                         b'{"id":"invalid","status":"Accepted"}',
                         b'{"id":null,"status":"Accepted"}'):
            with self.subTest(response=response):
                self.commands.clear()
                with self.assertRaisesRegex(ValueError, "invalid JSON/id"):
                    self.attempt(stdout=response)
                self.assert_no_staple()
        self.assertEqual(len(list((self.root / "logs").glob("*/submit.json"))), 6)

    def test_failed_log_download_does_not_hide_original_rejection(self):
        with self.assertRaisesRegex(ValueError, "status=Invalid"):
            self.attempt(status="Invalid", log_exit=1)
        self.assert_no_staple()
        self.assertTrue(next((self.root / "logs").glob("*/log.stderr.txt")).is_file())

    def test_attempts_are_isolated_from_a_previous_accepted_result(self):
        accepted = self.attempt()
        self.commands.clear()
        with self.assertRaises(ValueError):
            self.attempt(status="Invalid")
        self.assert_no_staple()
        self.assertEqual(json.loads((accepted / "submit.json").read_text())["status"], "Accepted")
        self.assertEqual(len(list((self.root / "logs").iterdir())), 2)

    def test_explicit_keychain_is_used_for_submit_and_log(self):
        with patch.object(notary.subprocess, "run", side_effect=self.fake_run()):
            notary.notarize(self.package, "test-profile", self.root / "logs", self.root / "signing.keychain-db")
        for command in self.commands[:2]:
            self.assertEqual(command[command.index("--keychain") + 1], str(self.root / "signing.keychain-db"))

    def test_stapler_failure_stops_before_validation(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.attempt(staple_exit=65)
        self.assertEqual([command[2] for command in self.commands], ["submit", "log", "staple"])

    def test_installer_and_workflow_use_status_gate_and_always_upload_only_logs(self):
        installer = (ROOT / "Installer/build.sh").read_text()
        self.assertIn("../update/notarize-macos.py", installer)
        self.assertNotIn("xcrun stapler staple", installer)
        workflow = (ROOT / ".github/workflows/package-macos.yml").read_text()
        step = workflow.split("- name: Upload notarization diagnostics even on failure", 1)[1].split("- name:", 1)[0]
        self.assertIn("if: always()", step)
        self.assertIn("path: ${{ runner.temp }}/keykey-notary/", step)
        self.assertIn("if-no-files-found: ignore", step)


if __name__ == "__main__":
    unittest.main()
