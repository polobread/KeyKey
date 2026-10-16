"""Exercise package script routing with fake commands; never install or run TIS."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


class PostinstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="keykey installer test ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.calls = self.root / "calls"
        stat = self.root / "stat"
        stat.write_text('#!/bin/bash\nprintf "%s\\n" "$TEST_CONSOLE_UID"\n')
        launch = self.root / "launchctl"
        launch.write_text('#!/bin/bash\nprintf "%s\\n" "$@" > "$TEST_CALLS"\nexit "$TEST_RESULT"\n')
        stat.chmod(0o755)
        launch.chmod(0o755)
        source = Path(__file__).resolve().parents[1] / "Scripts/postinstall"
        self.script = self.root / "postinstall"
        self.script.write_text(source.read_text().replace("/usr/bin/stat", shlex.quote(str(stat)))
                               .replace("/bin/launchctl", shlex.quote(str(launch))))

    def run_script(self, uid="501", result="0", volume="/"):
        return subprocess.run(["/bin/bash", str(self.script), "package", "/", volume],
                              env={**os.environ, "TEST_CONSOLE_UID": uid, "TEST_CALLS": str(self.calls),
                                   "TEST_RESULT": result}, capture_output=True, text=True)

    def test_console_user_and_gui_namespace(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().splitlines(), [
            "asuser", "501", "/usr/bin/sudo", "-H", "-u", "#501", "--",
            "/Library/Input Methods/chichi77 KeyKey.app/Contents/MacOS/KeyKeyInputSourceTool",
            "--refresh"])

    def test_non_startup_volume_does_not_touch_current_session(self):
        self.assertEqual(self.run_script(volume="/Volumes/Other Mac").returncode, 0)
        self.assertFalse(self.calls.exists())

    def test_no_login_and_setup_accounts_are_skipped(self):
        for uid in ("0", "248", "invalid"):
            with self.subTest(uid=uid):
                self.assertEqual(self.run_script(uid=uid).returncode, 0)
                self.assertFalse(self.calls.exists())

    def test_failed_refresh_and_timeout_preserve_completed_package_install(self):
        for status in ("1", "124", "75"):
            with self.subTest(status=status):
                result = self.run_script(result=status)
                self.assertEqual(result.returncode, 0)
                self.assertIn("files were installed", result.stderr)
                self.assertIn("before logging out", result.stderr)


if __name__ == "__main__":
    unittest.main()
