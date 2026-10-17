#!/usr/bin/env python3
"""Check removal against real dpkg-query with an isolated status database."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / "ci/verify-debian-package-removal.sh"
PACKAGES = ("chichi77-keykey-data", "fcitx5-chichi77-keykey")


@unittest.skipUnless(shutil.which("dpkg-query"), "requires Debian dpkg-query")
class PackageRemovalTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.status = self.directory / "status"
        self.env = dict(os.environ, DPKG_ADMINDIR=str(self.directory), LC_ALL="C")
        self.env.pop("DPKG_ROOT", None)

    def database(self, states):
        states = dict(states)
        if "triggers-awaited" in states.values():
            states["keykey-trigger-fixture"] = "triggers-pending"
        entries = []
        for package, state in states.items():
            entries.append(
                f"Package: {package}\nStatus: deinstall ok {state}\n"
                "Architecture: all\nVersion: 1.3.2-1\n"
                "Maintainer: Test <test@example.invalid>\n"
                "Description: Isolated package removal fixture\n"
                + ("Triggers-Awaited: keykey-trigger-fixture\n"
                   if state == "triggers-awaited" else "")
                + ("Triggers-Pending: keykey-test-trigger\n"
                   if state == "triggers-pending" else "")
                + ("Conffiles:\n /etc/xdg/autostart/org.chichi77.KeyKey.UpdateNotification.desktop "
                   "0123456789abcdef0123456789abcdef\n" if state == "config-files" else "")
                + "\n")
        self.status.write_text("".join(entries), encoding="utf-8")

    def check(self, expected):
        result = subprocess.run(["bash", str(HELPER), *PACKAGES], env=self.env,
                                text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def test_absent_packages_are_removed(self):
        self.database({})
        self.check(0)

    def test_retained_conffiles_are_removed_even_when_query_succeeds(self):
        self.database(dict.fromkeys(PACKAGES, "config-files"))
        query = subprocess.run(["dpkg-query", "-W", *PACKAGES], env=self.env,
                               text=True, capture_output=True, timeout=5)
        self.assertEqual(query.returncode, 0)  # Reproduces the old false failure.
        self.assertIn("config-files", self.check(0).stdout)

    def test_config_files_and_absent_package_are_removed(self):
        for package in PACKAGES:
            with self.subTest(package=package):
                self.database({package: "config-files"})
                self.check(0)

    def test_not_installed_record_is_removed(self):
        self.database(dict.fromkeys(PACKAGES, "not-installed"))
        self.check(0)

    def test_installed_package_cannot_be_hidden_by_missing_package(self):
        for package in PACKAGES:
            with self.subTest(package=package):
                self.database({package: "installed"})
                self.assertIn(package, self.check(1).stderr)

    def test_incomplete_removal_is_rejected(self):
        for state in ("half-installed", "unpacked", "half-configured",
                      "triggers-awaited", "triggers-pending"):
            with self.subTest(state=state):
                self.database({PACKAGES[0]: state})
                query = subprocess.run(
                    ["dpkg-query", "-W", "-f=${db:Status-Status}", PACKAGES[0]],
                    env=self.env, text=True, capture_output=True, timeout=5)
                self.assertEqual(query.returncode, 0, query.stderr)
                self.assertEqual(query.stdout, state)
                self.assertIn(state, self.check(1).stderr)

    def test_database_error_is_not_treated_as_removal(self):
        self.status.write_text("invalid status database\n", encoding="utf-8")
        self.assertIn("dpkg-query failed", self.check(2).stderr)


if __name__ == "__main__":
    unittest.main()
