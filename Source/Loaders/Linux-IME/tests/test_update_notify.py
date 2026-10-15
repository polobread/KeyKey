#!/usr/bin/env python3
"""Network-free update regressions, including the FreeBSD ports boundary."""
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import update_notify as updates


def release(version, assets=True):
    base = version.split("-beta")[0]
    return {"tag_name": "v" + version, "draft": False,
            "prerelease": "-beta" in version,
            "html_url": "https://evil.invalid/installer",
            "assets": [{"name": name, "size": 20, "state": "uploaded"} for name in (
                f"chichi77-keykey-data_{base}-1+ubuntu24.04_all.deb",
                f"fcitx5-chichi77-keykey_{base}-1+ubuntu24.04_amd64.deb")]
            if assets else []}


class ReleaseTests(unittest.TestCase):
    def check(self, releases, system="Linux", current="1.3.1", beta=False,
              source="1.3.2", machine="x86_64"):
        self.urls = []
        def get(url):
            self.urls.append(url)
            return (json.dumps(releases).encode() if url == updates.API else
                    f"project(KeyKeyLinux VERSION {source} LANGUAGES CXX)\n".encode())
        return updates.latest_release(current, system, machine, beta, get)

    def test_order(self):
        ordered = ["1.3.2-beta1", "1.3.2-beta9", "1.3.2-beta10", "1.3.2", "1.3.10", "1.10.0"]
        self.assertEqual(ordered, sorted(ordered, key=updates.version_key))

    def test_invalid_versions(self):
        for version in ("1.3", "01.3.2", "1.3.2-beta0", "1.3.2-beta01", "1.3.2_1", "1.3.2/evil"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                updates.version_key(version)

    def test_stable_ignores_beta(self):
        self.assertIsNone(self.check([release("1.3.2-beta1")]))
        self.assertEqual(self.urls, [updates.API])

    def test_explicit_beta_opt_in(self):
        self.assertEqual(self.check([release("1.3.2-beta10")], beta=True)["version"], "1.3.2-beta10")

    def test_beta_can_upgrade_to_stable(self):
        self.assertEqual(self.check([release("1.3.2")], current="1.3.2-beta1")["version"], "1.3.2")

    def test_no_downgrade_or_same_version(self):
        self.assertIsNone(self.check([release("1.3.1"), release("1.3.2-beta10")], current="1.3.2", beta=True))

    def test_linux_requires_complete_matching_architecture(self):
        self.assertIsNone(self.check([release("1.3.2", assets=False)]))
        self.assertIsNone(self.check([release("1.3.2")], machine="aarch64"))
        self.assertIsNone(self.check([release("1.3.2")], machine="riscv64"))

    def test_freebsd_does_not_require_deb(self):
        result = self.check([release("1.3.2", assets=False)], system="FreeBSD", machine="amd64")
        self.assertEqual(result, {"version": "1.3.2", "url": updates.RELEASES + "/tag/v1.3.2"})

    def test_mobile_tag_is_not_unix_upgrade(self):
        for system in ("Linux", "FreeBSD"):
            with self.subTest(system=system):
                self.assertIsNone(self.check([release("1.3.3")], system=system, source="1.3.2"))

    def test_invalid_source_and_untrusted_url(self):
        self.assertIsNone(self.check([release("1.3.2")], source="garbage"))
        self.assertEqual(self.check([release("1.3.2")])["url"], updates.RELEASES + "/tag/v1.3.2")

    def test_drafts_and_inconsistent_channel(self):
        for changes in ({"draft": True}, {"prerelease": True}, {"tag_name": "v1.3.2/../bad"}):
            value = release("1.3.2")
            value.update(changes)
            self.assertIsNone(self.check([value], beta=True))

    def test_api_error(self):
        for data in (b"bad json", b'{"message": "rate limit"}'):
            with self.assertRaises(ValueError):
                updates.latest_release("1.3.1", "FreeBSD", "amd64", get=lambda _: data)

    def test_https_redirect_boundary(self):
        from urllib.request import Request
        request = Request(updates.API)
        for url in ("http://api.github.com/data", "https://evil.invalid", "https://api.github.com:444/data"):
            with self.assertRaises(ValueError):
                updates.SameHostRedirect().redirect_request(request, None, 302, "", {}, url)

    def test_total_deadline_covers_all_requests(self):
        calls = []
        clock = [0]
        def get(url):
            calls.append(url)
            clock[0] += 6
            return (json.dumps([release("1.3.2")]).encode() if url == updates.API else
                    b"project(KeyKeyLinux VERSION 1.3.2 LANGUAGES CXX)\n")
        with patch.object(updates.time, "monotonic", side_effect=lambda: clock[0]):
            with self.assertRaises(TimeoutError):
                updates.latest_release("1.3.1", "Linux", "x86_64", get=get)
        self.assertEqual(len(calls), 2)

    def test_cancelled_check_starts_no_further_requests(self):
        cancelled = threading.Event()
        calls = []
        def get(url):
            calls.append(url)
            cancelled.set()
            return json.dumps([release("1.3.2")]).encode()
        with self.assertRaises(TimeoutError):
            updates.latest_release("1.3.1", "Linux", "x86_64", get=get, cancelled=cancelled)
        self.assertEqual(calls, [updates.API])

    def test_trickling_response_cannot_extend_query_forever(self):
        clock = [0]
        class Response:
            def __enter__(self): return self
            def __exit__(self, *_): pass
            def read1(self, _):
                clock[0] += 6
                return b"x"
        with patch.object(updates, "build_opener") as opener, \
                patch.object(updates.time, "monotonic", side_effect=lambda: clock[0]):
            opener.return_value.open.return_value = Response()
            with self.assertRaises(TimeoutError):
                updates.fetch(updates.API)
        self.assertEqual(clock[0], 12)


class PreferenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = patch.dict(os.environ, {"XDG_CONFIG_HOME": str(self.root / "config"),
                                          "XDG_STATE_HOME": str(self.root / "state")})
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_default_off_and_invalid_consent(self):
        self.assertEqual(updates.preferences(), {"enabled": False, "include_beta": False})
        path = updates.config_home() / "chichi77-keykey/update-notification.json"
        for enabled in ("true", 1, None):
            updates.save_json(path, {"enabled": enabled})
            self.assertFalse(updates.preferences()["enabled"])
        path.write_text("corrupt", encoding="utf-8")
        self.assertFalse(updates.preferences()["enabled"])

    def test_freebsd_prefix_and_enable_disable(self):
        executable = "/usr/local/bin/keykey-update-notify"
        updates.set_preferences(True, False, executable)
        path = updates.config_home() / "autostart/org.chichi77.KeyKey.UpdateNotification.desktop"
        self.assertIn(f'Exec="{executable}" --background', path.read_text(encoding="utf-8"))
        self.assertTrue(updates.preferences()["enabled"])
        updates.set_preferences(False, True, executable)
        self.assertFalse(path.exists())
        self.assertEqual(updates.preferences(), {"enabled": False, "include_beta": True})

    def test_daily_throttle_and_clock_rollback(self):
        self.assertTrue(updates.due({}, now=100000))
        self.assertFalse(updates.due({"last_attempt": 100000}, now=100060))
        self.assertTrue(updates.due({"last_attempt": 100000}, now=186400))
        self.assertTrue(updates.due({"last_attempt": 200000}, now=100000))
        self.assertTrue(updates.due({"last_attempt": "corrupt"}, now=100000))
        self.assertTrue(updates.due({"last_attempt": float("nan")}, now=100000))

    def test_atomic_state_roundtrip(self):
        path = updates.state_home() / "chichi77-keykey/update-notification.json"
        value = {"last_attempt": 12345, "last_notified": "1.3.2"}
        updates.save_json(path, value)
        self.assertEqual(updates.load_json(path), value)
        self.assertEqual(len(list(path.parent.iterdir())), 1)


if __name__ == "__main__":
    unittest.main()
