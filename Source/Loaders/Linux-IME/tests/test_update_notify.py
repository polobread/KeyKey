#!/usr/bin/env python3
"""Network-free update regressions, including the FreeBSD ports boundary."""
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import update_notify as updates


def feed(*versions, architectures=("amd64",)):
    root = ET.Element("rss", version="2.0")
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "Unix notifications"
    ET.SubElement(channel, f"{{{updates.UNIX}}}schemaVersion").text = "1"
    for version in versions:
        key = updates.version_key(version)
        item = ET.SubElement(channel, "item")
        ET.SubElement(item, f"{{{updates.SPARKLE}}}shortVersionString").text = version
        ET.SubElement(item, f"{{{updates.SPARKLE}}}version").text = (
            ".".join(str(part) for part in key[:3]) + ("" if key[3] else f"b{key[4]}"))
        ET.SubElement(item, "link").text = updates.RELEASES + "/tag/v" + version
        for arch in architectures:
            ET.SubElement(item, f"{{{updates.UNIX}}}linuxArchitecture").text = arch
    return ET.tostring(root, encoding="utf-8")


class ReleaseTests(unittest.TestCase):
    def check(self, versions=(), system="Linux", current="1.3.1", beta=False,
              betas=(), machine="x86_64", architectures=("amd64",)):
        self.urls = []
        def get(url):
            self.urls.append(url)
            self.assertIn(url, updates.FEEDS.values())
            return feed(*(betas if url == updates.FEEDS["beta"] else versions),
                        architectures=architectures)
        return updates.latest_release(current, system, machine, beta, get)

    def test_order(self):
        ordered = ["1.3.2-beta1", "1.3.2-beta9", "1.3.2-beta10", "1.3.2", "1.3.10", "1.10.0"]
        self.assertEqual(ordered, sorted(ordered, key=updates.version_key))

    def test_invalid_versions(self):
        for version in ("1.3", "01.3.2", "1.3.2-beta0", "1.3.2-beta01", "1.3.2_1", "1.3.2/evil"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                updates.version_key(version)

    def test_stable_checks_only_one_fixed_cdn_url(self):
        self.assertIsNone(self.check(betas=("1.3.2-beta1",)))
        self.assertEqual(self.urls, [updates.FEEDS["stable"]])

    def test_explicit_beta_opt_in_checks_both_channels(self):
        self.assertEqual(self.check(beta=True, betas=("1.3.2-beta10",))["version"], "1.3.2-beta10")
        self.assertEqual(self.urls, [updates.FEEDS["stable"], updates.FEEDS["beta"]])

    def test_beta_can_upgrade_to_stable(self):
        self.assertEqual(self.check(("1.3.2",), current="1.3.2-beta1")["version"], "1.3.2")
        self.assertEqual(self.check(("1.3.2",), beta=True, betas=("1.3.2-beta10",))["version"], "1.3.2")

    def test_no_downgrade_or_same_version(self):
        self.assertIsNone(self.check(("1.3.1", "1.3.2"), current="1.3.2", beta=True,
                                     betas=("1.3.2-beta10",)))

    def test_newest_version_wins_independent_of_item_order(self):
        self.assertEqual(self.check(("1.3.2", "1.4.0", "1.3.10"))["version"], "1.4.0")

    def test_linux_requires_reviewed_matching_architecture(self):
        self.assertIsNone(self.check(("1.3.2",), machine="aarch64"))
        self.assertIsNone(self.check(("1.3.2",), machine="riscv64"))
        for machine in ("aarch64", "arm64"):
            self.assertEqual(self.check(("1.3.2",), machine=machine,
                                       architectures=("amd64", "arm64"))["version"], "1.3.2")

    def test_freebsd_shares_feed_without_waiting_or_querying_pkg(self):
        result = self.check(("1.3.2",), system="FreeBSD", machine="amd64")
        self.assertEqual(result, {"version": "1.3.2", "url": updates.RELEASES + "/tag/v1.3.2"})
        self.assertEqual(self.urls, [updates.FEEDS["stable"]])

    def test_unsupported_platform_is_rejected_without_network(self):
        with self.assertRaises(ValueError):
            updates.latest_release("1.3.1", "Windows", "amd64", get=lambda _: self.fail("network"))

    def test_inconsistent_version_channel_link_architecture_or_enclosure_rejected(self):
        source = feed("1.3.2")
        variants = [source.replace(b"/tag/v1.3.2", b"/tag/v1.3.3"),
                    source.replace(b"https://github.com", b"https://evil.invalid"),
                    source.replace(b"amd64", b"riscv64"),
                    source.replace(b"</item>", b'<enclosure url="https://evil.invalid/install"/></item>')]
        document = ET.fromstring(source)
        document.find(f"./channel/item/{{{updates.SPARKLE}}}version").text = "1.3.3"
        variants.extend([ET.tostring(document), feed("1.3.2-beta1"), feed("1.3.2", architectures=()),
                         feed("1.3.2", "1.3.2"), feed("1.3.2", architectures=("amd64", "amd64"))])
        for data in variants:
            with self.subTest(data=data), self.assertRaises(ValueError):
                updates.parse_feed(data, "stable")
        with self.assertRaises(ValueError):
            updates.parse_feed(source, "beta")

    def test_xml_errors_dtd_utf16_oversize_and_schema_rejected(self):
        for data in (b"", b"not xml", b"<not-rss/>", b"x" * (updates.LIMIT + 1),
                     b'<!DOCTYPE rss>' + feed(), ('<!DOCTYPE rss>' + feed().decode()).encode("utf-16"),
                     ('<!DOCTYPE rss>' + feed().decode()).encode("utf-16-be"),
                     ('<!DOCTYPE rss>' + feed().decode()).encode("utf-16-le"),
                     feed().replace(b">1<", b">2<"), feed().replace(b"</rss>", b"<channel/></rss>")):
            with self.subTest(data=data[:30]), self.assertRaises((ValueError, UnicodeError, ET.ParseError)):
                updates.parse_feed(data, "stable")

    def test_missing_or_duplicate_version_link_field_is_rejected(self):
        for field in ("link", f"{{{updates.SPARKLE}}}version", f"{{{updates.SPARKLE}}}shortVersionString"):
            for duplicate in (False, True):
                root = ET.fromstring(feed("1.3.2"))
                item = root.find("./channel/item")
                if duplicate:
                    ET.SubElement(item, field).text = item.findtext(field)
                else:
                    item.remove(item.find(field))
                with self.subTest(field=field, duplicate=duplicate), self.assertRaises(ValueError):
                    updates.parse_feed(ET.tostring(root), "stable")

    def test_https_redirect_boundary(self):
        from urllib.request import Request
        request = Request(updates.FEEDS["stable"])
        for url in ("http://download.aws.polobread.com/data", "https://evil.invalid", "https://download.aws.polobread.com:444/data"):
            with self.assertRaises(ValueError):
                updates.SameHostRedirect().redirect_request(request, None, 302, "", {}, url)

    def test_total_deadline_covers_both_feeds(self):
        calls, clock = [], [0]
        def get(url):
            calls.append(url)
            clock[0] += 6
            return feed()
        with patch.object(updates.time, "monotonic", side_effect=lambda: clock[0]):
            with self.assertRaises(TimeoutError):
                updates.latest_release("1.3.1", "Linux", "x86_64", include_beta=True, get=get)
        self.assertEqual(calls, [updates.FEEDS["stable"], updates.FEEDS["beta"]])

    def test_cancelled_check_starts_no_further_requests(self):
        cancelled, calls = threading.Event(), []
        def get(url):
            calls.append(url)
            cancelled.set()
            return feed()
        with self.assertRaises(TimeoutError):
            updates.latest_release("1.3.1", "Linux", "x86_64", include_beta=True, get=get, cancelled=cancelled)
        self.assertEqual(calls, [updates.FEEDS["stable"]])

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
                updates.fetch(updates.FEEDS["stable"])
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

    def test_default_on_and_invalid_settings(self):
        self.assertEqual(updates.preferences(), {"enabled": True, "include_beta": False})
        path = updates.config_home() / "chichi77-keykey/update-notification.json"
        for enabled in (False, "true", 1, None):
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

    def test_weekly_throttle_and_clock_rollback(self):
        self.assertTrue(updates.due({}, now=100000))
        self.assertFalse(updates.due({"last_attempt": 100000}, now=704799))
        self.assertTrue(updates.due({"last_attempt": 100000}, now=704800))
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
