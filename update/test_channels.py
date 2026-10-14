# Copyright (c) 2026 Chui Ping Cheng. MIT License.
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

import channels
import prepare


class ChannelTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = dict(schema_version=1, public_ed25519_key="",
            macos_feed_url="", windows_x64_feed_url="", windows_x86_feed_url="")

    def test_tags_and_machine_versions(self):
        for tag, expected, machine in (("v1.3.2", "stable", "1.3.2"),
                ("v1.3.2-beta1", "beta", "1.3.2b1"), ("v1.3.2-beta2", "beta", "1.3.2b2"),
                ("v1.3.2-beta10", "beta", "1.3.2b10")):
            version = channels.release_version(tag, "1.3.2")
            self.assertEqual(channels.parse_version(version)[1], expected)
            self.assertEqual(channels.native_version(version), machine)
        for tag in ("v1.3.1-beta1", "v1.3.2-beta", "v1.3.2-beta0", "v1.3.2-beta01",
                    "v1.3.2-beta.1", "v1.3.2-rc1", "1.3.2-beta1", "v1.3.2-beta1\n"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                channels.release_version(tag, "1.3.2")

    def test_beta_build_keeps_both_endpoints_for_default_off_user_selection(self):
        import base64
        self.config.update(public_ed25519_key=base64.b64encode(bytes(32)).decode(),
            macos_feed_url="https://example.invalid/update/stable/macos-arm64.xml",
            windows_x64_feed_url="https://example.invalid/update/stable/windows-x64.xml",
            macos_beta_feed_url="https://example.invalid/update/beta/macos-arm64.xml")
        for tag in ("v1.3.2", "v1.3.2-beta1", "v1.3.2-beta2"):
            with patch.object(prepare, "load_config", return_value=dict(self.config)):
                output = self.root / tag / "config.json"
                prepare.select_release_config(tag, "1.3.2", output)
            result = json.loads(output.read_text())
            self.assertEqual(result["release_version"], tag[1:])
            self.assertEqual(result["channel_selection"], "user-opt-in")
            self.assertIn("/stable/", result["macos_feed_url"])
            self.assertIn("/beta/", result["macos_beta_feed_url"])
            self.assertIn("/stable/", result["windows_x64_feed_url"])
            self.assertEqual(result.get("windows_x64_beta_feed_url", ""), "")
        self.assertIn("/stable/", self.config["macos_feed_url"])

    def test_stamp_beta_bundle_without_changing_source_product_version(self):
        app = self.root / "Test.app"
        info_path = app / "Contents/Info.plist"
        info_path.parent.mkdir(parents=True)
        info_path.write_bytes(plistlib.dumps(dict(CFBundleVersion="1.3.2", CFBundleShortVersionString="1.3.2")))
        for beta in (1, 2, 10):
            with patch.object(prepare, "load_config", return_value=dict(self.config, release_version=f"1.3.2-beta{beta}")):
                prepare.stamp_macos(app)
            result = plistlib.loads(info_path.read_bytes())
            self.assertEqual(result["CFBundleVersion"], f"1.3.2b{beta}")
            self.assertEqual(result["CFBundleShortVersionString"], "1.3.2")
            self.assertEqual(result["KeyKeyReleaseVersion"], f"1.3.2-beta{beta}")
        with patch.object(prepare, "load_config", return_value=dict(self.config, release_version="1.3.3-beta1")):
            with self.assertRaisesRegex(ValueError, "product does not match"):
                prepare.stamp_macos(app)

    def test_generated_config_validation_rejects_bad_beta_url(self):
        config = self.root / "config.json"
        config.write_text(json.dumps(dict(self.config, macos_beta_feed_url="http://example.invalid/beta.xml")))
        with patch.dict(os.environ, KEYKEY_UPDATE_CONFIG=str(config)), self.assertRaises(ValueError):
            prepare.load_config()

    def test_generated_beta_config_cannot_select_stable_feed(self):
        config = self.root / "config.json"
        import base64
        result = dict(self.config, public_ed25519_key=base64.b64encode(bytes(32)).decode(),
            release_version="1.3.2-beta1", update_channel="beta",
            macos_feed_url="https://example.invalid/update/stable/macos-arm64.xml")
        config.write_text(json.dumps(result))
        with patch.dict(os.environ, KEYKEY_UPDATE_CONFIG=str(config)), self.assertRaisesRegex(ValueError, "only its reviewed beta feeds"):
            prepare.load_config()

    def test_selecting_stable_ignores_previously_exported_beta_config(self):
        original = self.root / "config.json"
        original.write_text(json.dumps(self.config))
        beta = self.root / "previous-beta.json"
        beta.write_text("invalid previous exported config must not be read")
        output = self.root / "stable.json"
        with patch.object(prepare, "ROOT", self.root), patch.dict(os.environ, KEYKEY_UPDATE_CONFIG=str(beta)):
            prepare.select_release_config("v1.3.2", "1.3.2", output)
        self.assertEqual(json.loads(output.read_text())["update_channel"], "stable")


if __name__ == "__main__":
    unittest.main()
