import base64
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

import metadata
import prepare

OPENSSL = os.environ.get("KEYKEY_TEST_OPENSSL", shutil.which("openssl"))


class MetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.key = self.root / "key.pem"
        subprocess.run([OPENSSL, "genpkey", "-algorithm", "ED25519", "-out", str(self.key)], check=True)
        self.public = metadata.public_key(self.key, OPENSSL)
        self.package = self.root / "KeyKey.pkg.zip"
        self.package.write_bytes(b"isolated-test-fixture-not-a-release-package")
        self.manifest = {"schema_version": 1, "channel": "stable", "releases": [dict(
            target="macos-arm64", version="1.3.2", release_tag="v1.3.2", source_sha="a" * 40,
            tag_sha="a" * 40, file=str(self.package), minimum_system_version="15.0.0", notes="修正 <輸入> & 選字")]}

    def build(self, manifest=None, pinned=None):
        with patch.object(metadata, "verify_platform_package"):
            return metadata.build(manifest or self.manifest, self.key, "https://downloads.example/keykey/releases/download",
                self.root / "out", pinned or self.public, OPENSSL)

    def test_real_signatures_and_tamper_rejection(self):
        self.build()
        path = self.root / "out" / "metadata.json"
        signature = path.with_name("metadata.json.sig").read_text().strip()
        metadata.verify(path, signature, self.public, OPENSSL)
        path.write_bytes(path.read_bytes() + b" ")
        with self.assertRaisesRegex(ValueError, "verification failed"):
            metadata.verify(path, signature, self.public, OPENSSL)

    def test_platform_feeds_and_immutable_package_signature(self):
        windows = self.root / "setup.exe"
        windows.write_bytes(b"isolated-windows-test")
        manifest = copy.deepcopy(self.manifest)
        entry = dict(manifest["releases"][0], target="windows-x64", file=str(windows), minimum_system_version="10.0.0")
        manifest["releases"].append(entry)
        result = self.build(manifest)
        self.assertEqual(result["package_managers"]["freebsd"], "ports/pkg")
        for release in result["releases"]:
            path = self.root / "out" / "packages" / release["name"]
            self.assertIn(release["sha256"], release["url"])
            metadata.verify(path, release["ed25519_signature"], self.public, OPENSSL)
            xml = ET.parse(self.root / "out" / f"{release['target']}.xml")
            enclosure = xml.find("./channel/item/enclosure")
            self.assertEqual(enclosure.attrib["url"], release["url"])
            self.assertEqual(enclosure.attrib[f"{{{metadata.SPARKLE}}}edSignature"], release["ed25519_signature"])
            self.assertIn("&lt;輸入&gt; &amp; 選字", xml.findtext("./channel/item/description"))
        mac = ET.parse(self.root / "out/macos-arm64.xml").find("./channel/item/enclosure")
        self.assertEqual(mac.attrib[f"{{{metadata.SPARKLE}}}installationType"], "package")

    def test_fail_closed_versions_unsigned_duplicates_and_recovery_build(self):
        for changes in (dict(version="1.3.2-beta"), dict(release_tag="v1.3.1"), dict(tag_sha="b" * 40),
                        dict(target="freebsd"), dict(file=str(self.root / "missing"))):
            with self.subTest(changes=changes):
                manifest = copy.deepcopy(self.manifest)
                manifest["releases"][0].update(changes)
                with self.assertRaises(ValueError):
                    metadata.validate_manifest(manifest)
        unsigned = self.root / "setup.unsigned.exe"
        unsigned.write_bytes(b"not-signed")
        manifest = copy.deepcopy(self.manifest)
        manifest["releases"][0].update(target="windows-x64", file=str(unsigned))
        with self.assertRaisesRegex(ValueError, "signed setup"):
            metadata.validate_manifest(manifest)
        manifest = copy.deepcopy(self.manifest)
        manifest["releases"].append(manifest["releases"][0])
        with self.assertRaisesRegex(ValueError, "duplicate"):
            metadata.validate_manifest(manifest)

    def test_wrong_key_and_os_verification_failure_produce_no_output(self):
        with self.assertRaisesRegex(ValueError, "reviewed public key"):
            self.build(pinned=base64.b64encode(bytes(32)).decode())
        with patch.object(metadata, "verify_platform_package", side_effect=ValueError("not notarized")):
            with self.assertRaisesRegex(ValueError, "not notarized"):
                metadata.build(self.manifest, self.key, "https://example.com", self.root / "out", self.public, OPENSSL)
        self.assertFalse((self.root / "out").exists())

    def test_existing_signed_output_is_never_overwritten(self):
        self.build()
        before = (self.root / "out/metadata.json").read_bytes()
        with self.assertRaisesRegex(ValueError, "must not exist"):
            self.build()
        self.assertEqual(before, (self.root / "out/metadata.json").read_bytes())

    def test_https_base_and_configuration(self):
        for url in ("http://example.com", "https://user:pass@example.com", "https://example.com/?a=b", "https://example.com/#feed"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                metadata.build(self.manifest, self.key, url, self.root / "out", self.public, OPENSSL)
        self.assertEqual(prepare.load_config()["schema_version"], 1)

    def test_combine_attestation_and_reject_changed_package(self):
        directory = self.root / "attestations"
        with patch.object(metadata, "verify_platform_package"):
            metadata.attest(self.manifest, self.key, directory, self.public, OPENSSL)
        entry = self.manifest["releases"][0]
        metadata.verify_attestation(entry, directory, self.public, OPENSSL)
        with patch.object(metadata, "verify_platform_package") as os_check:
            metadata.build(self.manifest, self.key, "https://example.com/download", self.root / "out",
                self.public, OPENSSL, directory)
            os_check.assert_not_called()
        self.package.write_bytes(b"changed-after-platform-verification")
        with self.assertRaisesRegex(ValueError, "does not match"):
            metadata.verify_attestation(entry, directory, self.public, OPENSSL)

    def test_os_gate_cannot_sign_fake_mac_package(self):
        with self.assertRaises(Exception):
            metadata.verify_platform_package(self.manifest["releases"][0])

    def test_signature_cannot_be_verified_with_a_different_key(self):
        signature = metadata.sign(self.package, self.key, OPENSSL)
        with self.assertRaisesRegex(ValueError, "verification failed"):
            metadata.verify(self.package, signature, base64.b64encode(bytes(32)).decode(), OPENSSL)


if __name__ == "__main__":
    unittest.main()
