"""Run real pre/postinstall scripts with fake TIS routing, never install."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
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
        # Simulate Installer/sudo carrying root's CoreFoundation user marker.
        # Execute the real env wrapper, replacing only the native helper with a
        # harmless probe; no actual launchctl, sudo, TIS or input method runs.
        probe = self.root / "helper-probe"
        probe.write_text('''#!/bin/bash
if [[ ${__CF_USER_TEXT_ENCODING+present} ]]; then
    echo "Root CoreFoundation user marker reached the GUI helper" >&2
    exit 91
fi
exit "$TEST_RESULT"
''')
        probe.chmod(0o755)
        launch.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$TEST_CALLS"
while (( $# )) && [[ "$1" != -- ]]; do shift; done
(( $# )) || exit 92
shift
command=("$@")
for index in "${!command[@]}"; do
    if [[ "${command[$index]}" == */KeyKeyInputSourceTool ]]; then
        command[$index]="$TEST_ENV_PROBE"
    fi
done
exec "${command[@]}"
''')
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
                   arm64="1", sysctl_result="0"):
        return subprocess.run(["/bin/bash", str(self.root / name), "package", "/", volume],
            env={**os.environ, "TEST_CONSOLE_UID": uid, "TEST_CALLS": str(self.calls),
                 "TEST_RESULT": result, "TEST_STAT_RESULT": stat_result,
                 "TEST_ARM64": arm64, "TEST_SYSCTL_RESULT": sysctl_result,
                 "TEST_ENV_PROBE": str(self.root / "helper-probe"),
                 "__CF_USER_TEXT_ENCODING": "0x0:2:53"},
            capture_output=True, text=True, timeout=5)

    def helper_calls(self):
        return self.calls.read_text().splitlines() if self.calls.exists() else []

    def test_upgrade_prepares_old_process_and_finishes_without_state_restoration(self):
        self.assertEqual(self.run_script("preinstall").returncode, 0)
        self.assertEqual(self.run_script("postinstall").returncode, 0)
        calls = self.helper_calls()
        self.assertEqual(len(calls), 2)
        self.assertIn("asuser 501 /usr/bin/sudo -H -u #501 -- ", calls[0])
        self.assertTrue(calls[0].endswith(" --prepare-upgrade"))
        self.assertTrue(calls[1].endswith(" --finish-upgrade"))
        helper_path = calls[0].split(" -- /usr/bin/env -u __CF_USER_TEXT_ENCODING ", 1)[1].removesuffix(" --prepare-upgrade")
        self.assertFalse(Path(helper_path).exists(), "temporary preflight helper is cleaned up")
        self.assertFalse((self.root / "keykey-input-source-state").exists())

    def test_fresh_install_needs_no_preflight_helper_or_state(self):
        self.installed_app.rmdir()
        (self.root / "KeyKeyInputSourceTool").unlink()
        result = self.run_script("preinstall", result="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.helper_calls())
        self.assertFalse((self.root / "keykey-input-source-state").exists())

    def test_intel_and_unknown_hardware_stop_before_helper(self):
        for arm64, status in (("0", "0"), ("", "1"), ("unexpected", "0")):
            with self.subTest(arm64=arm64, status=status):
                result = self.run_script("preinstall", arm64=arm64, sysctl_result=status)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Apple Silicon", result.stderr)
                self.assertIn("Intel", result.stderr)
                self.assertFalse(self.helper_calls())

    def test_existing_file_or_dangling_symlink_keeps_upgrade_protection(self):
        self.installed_app.rmdir()
        for kind in ("file", "symlink"):
            with self.subTest(kind=kind):
                if kind == "file":
                    self.installed_app.write_text("incomplete old installation")
                else:
                    self.installed_app.symlink_to(self.root / "missing old bundle")
                self.calls.unlink(missing_ok=True)
                self.assertNotEqual(self.run_script("preinstall", result="1").returncode, 0)
                self.assertEqual(len(self.helper_calls()), 1)
                self.installed_app.unlink()

    def test_no_console_or_other_volume_does_not_touch_gui(self):
        for args in ({"volume": "/Volumes/Other Mac"}, {"uid": "0"}, {"uid": "248"},
                     {"uid": "invalid"}, {"stat_result": "1"}):
            for name in ("preinstall", "postinstall"):
                self.assertEqual(self.run_script(name, **args).returncode, 0)
            self.assertFalse(self.helper_calls())

    def test_unconfirmed_old_exit_blocks_replacement(self):
        for status in ("1", "124", "75"):
            with self.subTest(status=status):
                self.assertNotEqual(self.run_script("preinstall", result=status).returncode, 0)

    def test_postinstall_failure_preserves_completed_install_and_requires_login(self):
        for status in ("0", "1", "124", "75"):
            with self.subTest(status=status):
                self.calls.unlink(missing_ok=True)
                result = self.run_script("postinstall", result=status)
                self.assertEqual(result.returncode, 0)
                self.assertIn("log out of macOS and log back in", result.stdout)
                self.assertEqual(len(self.helper_calls()), 1)
                self.assertEqual(bool(result.stderr), status != "0")

    def test_changed_console_user_never_restores_another_users_state(self):
        self.assertEqual(self.run_script("preinstall").returncode, 0)
        self.assertEqual(self.run_script("postinstall", uid="502").returncode, 0)
        self.assertEqual(len(self.helper_calls()), 2)
        self.assertTrue(self.helper_calls()[1].startswith("asuser 502 "))
        self.assertTrue(self.helper_calls()[1].endswith(" --finish-upgrade"))


if __name__ == "__main__":
    unittest.main()
