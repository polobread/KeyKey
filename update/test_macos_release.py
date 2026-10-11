import base64
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

import macos_release
import metadata
import prepare

OPENSSL = os.environ.get("KEYKEY_TEST_OPENSSL", shutil.which("openssl"))


class MacReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.key = self.root / "test-private.pem"
        subprocess.run([OPENSSL, "genpkey", "-algorithm", "ED25519", "-out", str(self.key)], check=True)
        self.public = metadata.public_key(self.key, OPENSSL)
        self.package = self.root / "test.pkg.zip"
        self.package.write_bytes(b"isolated-artifact-test-not-a-notarized-package")
        self.config = dict(schema_version=1, public_ed25519_key=self.public,
            macos_feed_url="https://example.invalid/macos-arm64.xml", windows_x64_feed_url="", windows_x86_feed_url="")

    def candidate(self, source="a" * 40, tag="a" * 40, version="1.3.2", config=None):
        with patch.object(macos_release, "source_version", return_value="1.3.2"), \
             patch.object(prepare, "load_config", return_value=config or self.config):
            return macos_release.prepare_candidate(self.package, version, "v1.3.2", source, tag,
                self.key, "https://example.invalid/keykey/releases/download", self.root / "out", OPENSSL)

    def test_four_bundle_versions_do_not_depend_on_linux_readme(self):
        for name in macos_release.PLISTS:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(plistlib.dumps(dict(CFBundleVersion="1.3.2", CFBundleShortVersionString="1.3.2")))
        (self.root / "README.md").write_text("Linux 1.3.1\n")
        self.assertEqual(macos_release.source_version(self.root), "1.3.2")
        path.write_bytes(plistlib.dumps(dict(CFBundleVersion="1.3.2", CFBundleShortVersionString="1.3.1")))
        with self.assertRaisesRegex(ValueError, "four macOS bundles"):
            macos_release.source_version(self.root)

    def test_candidate_contains_verified_immutable_packages_and_real_signatures(self):
        with patch.object(metadata, "verify_platform_package") as os_verification:
            result = self.candidate()
        os_verification.assert_called_once()
        entry = result["releases"][0]
        self.assertEqual(entry["target"], "macos-arm64")
        self.assertIn(entry["sha256"], entry["url"])
        package = self.root / "out/packages" / entry["name"]
        metadata.verify(package, entry["ed25519_signature"], self.public, OPENSSL)
        path = self.root / "out/metadata.json"
        metadata.verify(path, path.with_suffix(".json.sig").read_text().strip(), self.public, OPENSSL)
        xml = ET.parse(self.root / "out/macos-arm64.xml")
        self.assertEqual(xml.findtext(f"./channel/item/{{{metadata.SPARKLE}}}hardwareRequirements"), "arm64")
        self.assertEqual(xml.findtext(f"./channel/item/{{{metadata.SPARKLE}}}minimumSystemVersion"), "15.0.0")
        self.assertEqual(xml.find("./channel/item/enclosure").get(f"{{{metadata.SPARKLE}}}installationType"), "package")

    def test_unconfigured_feed_and_wrong_version_fail_before_signing(self):
        with patch.object(metadata, "build") as build:
            with self.assertRaisesRegex(ValueError, "macOS feed"):
                self.candidate(config=dict(self.config, macos_feed_url=""))
            with self.assertRaisesRegex(ValueError, "macOS sources"):
                self.candidate(version="1.3.1")
            build.assert_not_called()
        self.assertFalse((self.root / "out").exists())

    def test_recovery_build_and_wrong_private_key_are_not_auto_updates(self):
        with patch.object(metadata, "verify_platform_package") as gate:
            with self.assertRaisesRegex(ValueError, "release tag commit"):
                self.candidate(source="b" * 40)
            with self.assertRaisesRegex(ValueError, "reviewed public key"):
                self.candidate(config=dict(self.config, public_ed25519_key=base64.b64encode(bytes(32)).decode()))
            gate.assert_not_called()
        self.assertFalse((self.root / "out").exists())

    def test_failed_notarization_cannot_produce_candidate(self):
        with patch.object(metadata, "verify_platform_package", side_effect=ValueError("not notarized")):
            with self.assertRaisesRegex(ValueError, "not notarized"):
                self.candidate()
        self.assertFalse((self.root / "out").exists())

    def test_initial_feed_cannot_offer_unsigned_automatic_install(self):
        xml = ET.parse(Path(__file__).with_name("stable") / "macos-arm64.xml")
        self.assertIsNone(xml.find("./channel/item"))
        self.assertIsNone(xml.find(".//enclosure"))

    def test_embedded_settings_enforce_offline_opt_in_and_safe_package_defaults(self):
        sdk = self.root / ".cache/macos-2.10.0"
        (sdk / "Sparkle.framework").mkdir(parents=True)
        (sdk / "LICENSE").write_text("isolated license fixture")
        (self.root / "config.json").write_text(json.dumps(self.config))
        app = self.root / "Test.app"
        (app / "Contents").mkdir(parents=True)
        info_path = app / "Contents/Info.plist"
        info_path.write_bytes(plistlib.dumps(dict(CFBundleVersion="1.3.2", SUAutomaticallyUpdate=True,
            SUEnableAutomaticChecks=True, SUSendProfileInfo=True)))
        with patch.object(prepare, "ROOT", self.root):
            prepare.embed_macos(app)
        info = plistlib.loads(info_path.read_bytes())
        self.assertFalse(info["SUAutomaticallyUpdate"])
        self.assertFalse(info["SUEnableAutomaticChecks"])
        self.assertFalse(info["SUAllowsAutomaticUpdates"])
        self.assertFalse(info["SUSendProfileInfo"])
        self.assertTrue(info["SUVerifyUpdateBeforeExtraction"])
        self.assertEqual(info["SUPublicEDKey"], self.public)
        self.assertEqual(info["SUFeedURL"], self.config["macos_feed_url"])
        (self.root / "config.json").write_text(json.dumps(dict(self.config, public_ed25519_key="", macos_feed_url="")))
        with patch.object(prepare, "ROOT", self.root):
            prepare.embed_macos(app)
        info = plistlib.loads(info_path.read_bytes())
        self.assertNotIn("SUFeedURL", info)
        self.assertNotIn("SUPublicEDKey", info)


if __name__ == "__main__":
    unittest.main()
