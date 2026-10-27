"""Run real pre/postinstall scripts with fake TIS routing, never install."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import time
import unittest


class InstallerScriptsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="keykey installer test ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.calls = self.root / "calls"
        self.installed_app = self.root / "installed KeyKey.app"
        self.installed_app.mkdir()  # An existing, even incomplete, bundle is an upgrade.
        sysctl = self.root / "sysctl"
        sysctl.write_text('#!/bin/bash\nprintf "%s\\n" "$TEST_ARM64"\nexit "$TEST_SYSCTL_RESULT"\n')
        sysctl.chmod(0o755)
        stat = self.root / "stat"
        stat.write_text('#!/bin/bash\nprintf "%s\\n" "$TEST_CONSOLE_UID"\nexit "$TEST_STAT_RESULT"\n')
        launch = self.root / "launchctl"
        launch.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$TEST_CALLS"\n'
                          'if [[ "${!#}" == --snapshot || "${!#}" == --prepare-upgrade ]]; then\n'
                          ' printf "%s\\n" "$TEST_SNAPSHOT"\n exit "$TEST_SNAPSHOT_RESULT"\nfi\n'
                          'exit "$TEST_RESULT"\n')
        stat.chmod(0o755)
        launch.chmod(0o755)
        scripts = Path(__file__).resolve().parents[1] / "Scripts"
        for name in ("preinstall", "postinstall"):
            (self.root / name).write_text((scripts / name).read_text()
                .replace("/Library/Input Methods/chichi77 KeyKey.app", str(self.installed_app))
                .replace("/usr/sbin/sysctl", shlex.quote(str(sysctl)))
                .replace("/usr/bin/stat", shlex.quote(str(stat)))
                .replace("/bin/launchctl", shlex.quote(str(launch))))
        (self.root / "KeyKeyInputSourceTool").write_text("signed helper fixture; never executed")

    def run_script(self, name, uid="501", result="0", volume="/", stat_result="0",
                   snapshot="disabled", snapshot_result="0", arm64="1", sysctl_result="0"):
        return subprocess.run(["/bin/bash", str(self.root / name), "package", "/", volume],
            env={**os.environ, "TEST_CONSOLE_UID": uid, "TEST_CALLS": str(self.calls),
                 "TEST_RESULT": result, "TEST_STAT_RESULT": stat_result,
                 "TEST_SNAPSHOT": snapshot, "TEST_SNAPSHOT_RESULT": snapshot_result,
                 "TEST_ARM64": arm64, "TEST_SYSCTL_RESULT": sysctl_result},
            capture_output=True, text=True, timeout=5)

    def wait_calls(self, count):
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            calls = self.calls.read_text().splitlines()
            if len(calls) >= count:
                return calls
            time.sleep(0.01)
        self.fail(f"Only {calls!r}, expected {count} calls")

    def test_upgrade_captures_enabled_before_replacement(self):
        self.assertEqual(self.run_script("preinstall", snapshot="enabled").returncode, 0)
        state = self.root / "keykey-input-source-state"
        self.assertEqual(state.read_text(), "501 enabled\n")
        self.assertEqual(state.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.run_script("postinstall", snapshot="enabled").returncode, 0)
        calls = self.wait_calls(3)
        self.assertIn("asuser 501 /usr/bin/sudo -H -u #501 -- ", calls[0])
        self.assertTrue(calls[0].endswith("/KeyKeyInputSourceTool --prepare-upgrade"))
        helper_path = calls[0].split(" -- ", 1)[1].removesuffix(" --prepare-upgrade")
        self.assertFalse(Path(helper_path).exists(), "preflight helper is removed after snapshot")
        self.assertTrue(calls[1].endswith(" --refresh-enabled"))
        self.assertTrue(calls[2].endswith(" --snapshot"))

    def test_fresh_install_skips_preparation_and_does_not_enable(self):
        self.installed_app.rmdir()
        (self.root / "KeyKeyInputSourceTool").unlink()
        result = self.run_script("preinstall", snapshot="invalid", snapshot_result="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.calls.exists(), "no GUI helper runs before a fresh install")
        state = self.root / "keykey-input-source-state"
        self.assertEqual(state.read_text(), "501 fresh\n")
        self.assertEqual(state.stat().st_mode & 0o777, 0o600)
        result = self.run_script("postinstall", snapshot_result="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("setup needs attention", result.stderr)
        self.assertEqual(len(self.wait_calls(1)), 1)
        self.assertTrue(self.calls.read_text().strip().endswith(" --refresh"))

    def test_fresh_install_registration_failure_is_nonfatal_and_shows_guidance(self):
        self.installed_app.rmdir()
        self.assertEqual(self.run_script("preinstall").returncode, 0)
        for status in ("1", "124", "75"):
            with self.subTest(status=status):
                self.calls.unlink(missing_ok=True)
                result = self.run_script("postinstall", result=status)
                self.assertEqual(result.returncode, 0)
                self.assertIn("setup needs attention", result.stderr)
                calls = self.wait_calls(2)
                self.assertTrue(calls[0].endswith(" --refresh"))
                self.assertTrue(calls[1].endswith(" --show-setup-warning"))

    def test_intel_and_unknown_hardware_stop_before_any_helper(self):
        for arm64, status in (("0", "0"), ("", "1"), ("unexpected", "0")):
            with self.subTest(arm64=arm64, status=status):
                result = self.run_script("preinstall", arm64=arm64, sysctl_result=status)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Apple Silicon", result.stderr)
                self.assertIn("Intel", result.stderr)
                self.assertFalse(self.calls.exists())
                self.assertFalse((self.root / "keykey-input-source-state").exists())

    def test_existing_file_or_dangling_symlink_keeps_upgrade_protection(self):
        self.installed_app.rmdir()
        for kind in ("file", "symlink"):
            with self.subTest(kind=kind):
                if kind == "file":
                    self.installed_app.write_text("incomplete old installation")
                else:
                    self.installed_app.symlink_to(self.root / "missing old bundle")
                self.calls.unlink(missing_ok=True)
                result = self.run_script("preinstall", snapshot_result="1")
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(self.wait_calls(1)[0].endswith(" --prepare-upgrade"))
                self.assertFalse((self.root / "keykey-input-source-state").exists())
                self.installed_app.unlink()

    def test_previously_disabled_upgrade_does_not_enable(self):
        self.assertEqual(self.run_script("preinstall").returncode, 0)
        self.assertEqual(self.run_script("postinstall").returncode, 0)
        self.assertTrue(self.wait_calls(2)[1].endswith(" --refresh"))

    def test_separate_process_must_confirm_restoration(self):
        self.assertEqual(self.run_script("preinstall", snapshot="enabled").returncode, 0)
        result = self.run_script("postinstall", snapshot="disabled")
        self.assertEqual(result.returncode, 0)
        self.assertIn("independent post-install enabled verification failed", result.stderr)
        calls = self.wait_calls(4)
        self.assertTrue(calls[1].endswith(" --refresh-enabled"))
        self.assertTrue(calls[2].endswith(" --snapshot"))
        self.assertTrue(calls[3].endswith(" --show-setup-warning"))

    def test_non_startup_volume_and_no_console_skip_both_phases(self):
        for args in ({"volume": "/Volumes/Other Mac"}, {"uid": "0"}, {"uid": "248"},
                     {"uid": "invalid"}, {"stat_result": "1"}):
            for name in ("preinstall", "postinstall"):
                self.assertEqual(self.run_script(name, **args).returncode, 0)
            self.assertFalse(self.calls.exists())

    def test_failed_preparation_prevents_payload_replacement(self):
        for status in ("1", "124", "75"):
            with self.subTest(status=status):
                result = self.run_script("preinstall", snapshot_result=status)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.root / "keykey-input-source-state").exists())

    def test_invalid_upgrade_snapshot_prevents_payload_replacement(self):
        result = self.run_script("preinstall", snapshot="invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid pre-install state", result.stderr)
        self.assertFalse((self.root / "keykey-input-source-state").exists())

    def test_changed_console_user_does_not_inherit_another_users_intent(self):
        self.assertEqual(self.run_script("preinstall", snapshot="enabled").returncode, 0)
        self.assertEqual(self.run_script("postinstall", uid="502").returncode, 0)
        calls = self.wait_calls(3)
        self.assertTrue(calls[1].startswith("asuser 502 "))
        self.assertTrue(calls[1].endswith(" --refresh"))
        self.assertTrue(calls[2].endswith(" --show-setup-warning"))

    def test_missing_or_malformed_snapshot_cannot_enable(self):
        for saved in (None, "501 unexpected\n", "501 enabled extra\n"):
            with self.subTest(saved=saved):
                self.calls.unlink(missing_ok=True)
                state = self.root / "keykey-input-source-state"
                state.unlink(missing_ok=True)
                if saved is not None:
                    state.write_text(saved)
                self.assertEqual(self.run_script("postinstall").returncode, 0)
                calls = self.wait_calls(2)
                self.assertTrue(calls[0].endswith(" --refresh"))
                self.assertTrue(calls[1].endswith(" --show-setup-warning"))

    def test_failed_restore_and_timeout_show_guidance_without_blocking_installer(self):
        self.assertEqual(self.run_script("preinstall", snapshot="enabled").returncode, 0)
        for status in ("1", "124", "75"):
            with self.subTest(status=status):
                self.calls.unlink(missing_ok=True)
                result = self.run_script("postinstall", result=status)
                self.assertEqual(result.returncode, 0)
                self.assertIn("setup needs attention", result.stderr)
                calls = self.wait_calls(2)
                self.assertTrue(calls[0].endswith(" --refresh-enabled"))
                self.assertTrue(calls[1].endswith(" --show-setup-warning"))


if __name__ == "__main__":
    unittest.main()
