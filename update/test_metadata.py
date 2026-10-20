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

    def test_beta_metadata_signature_and_machine_version(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["channel"] = "beta"
        entry = manifest["releases"][0]
        entry.update(version="1.3.2-beta2", release_tag="v1.3.2-beta2")
        result = self.build(manifest)
        self.assertEqual(result["channel"], "beta")
        self.assertIn("/v1.3.2-beta2/", result["releases"][0]["url"])
        xml = ET.parse(self.root / "out/macos-arm64.xml")
        self.assertEqual(xml.findtext(f"./channel/item/{{{metadata.SPARKLE}}}version"), "1.3.2b2")
        self.assertEqual(xml.findtext(f"./channel/item/{{{metadata.SPARKLE}}}shortVersionString"), "1.3.2-beta2")
        path = self.root / "out/metadata.json"
        metadata.verify(path, path.with_suffix(".json.sig").read_text().strip(), self.public, OPENSSL)

    def test_stable_and_beta_manifests_cannot_be_cross_promoted(self):
        for channel, version in (("stable", "1.3.2-beta1"), ("beta", "1.3.2")):
            manifest = copy.deepcopy(self.manifest)
            manifest["channel"] = channel
            manifest["releases"][0].update(version=version, release_tag="v" + version)
            with self.subTest(channel=channel), self.assertRaisesRegex(ValueError, "update channel"):
                metadata.validate_manifest(manifest)

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

    def test_unsigned_stable_requires_explicit_mode_and_keeps_package_signatures(self):
        unsigned = self.root / "setup.unsigned.exe"
        unsigned.write_bytes(b"unsigned-transition-fixture")
        manifest = copy.deepcopy(self.manifest)
        entry = manifest["releases"][0]
        entry.update(target="windows-x64", file=str(unsigned), minimum_system_version="10.0.0",
                     windows_signing="unsigned-transition")
        result = self.build(manifest)
        release = result["releases"][0]
        self.assertEqual(release["windows_signing"], "unsigned-transition")
        package = self.root / "out/packages" / release["name"]
        metadata.verify(package, release["ed25519_signature"], self.public, OPENSSL)
        description = ET.parse(self.root / "out/windows-x64.xml").findtext("./channel/item/description")
        self.assertIn("未知的發行者", description)
        self.assertIn("Ed25519", description)
        package.write_bytes(b"tampered-unsigned-installer")
        with self.assertRaisesRegex(ValueError, "verification failed"):
            metadata.verify(package, release["ed25519_signature"], self.public, OPENSSL)
        for changes in (dict(windows_signing="optional"), dict(windows_signing=None),
                        dict(target="macos-arm64"), dict(file=str(self.package))):
            with self.subTest(changes=changes):
                invalid = copy.deepcopy(manifest)
                invalid["releases"][0].update(changes)
                with self.assertRaises(ValueError):
                    metadata.validate_manifest(invalid)

    def test_unsigned_attestation_cannot_be_reused_for_signed_release(self):
        installer = self.root / "setup.exe"
        installer.write_bytes(b"unsigned-transition-fixture")
        manifest = copy.deepcopy(self.manifest)
        entry = manifest["releases"][0]
        entry.update(target="windows-x86", file=str(installer), windows_signing="unsigned-transition")
        directory = self.root / "attestations"
        with patch.object(metadata, "verify_platform_package"):
            metadata.attest(manifest, self.key, directory, self.public, OPENSSL)
        metadata.verify_attestation(entry, directory, self.public, OPENSSL)
        for mode in ("authenticode", None):
            changed = dict(entry)
            if mode is None:
                changed.pop("windows_signing")
            else:
                changed["windows_signing"] = mode
            with self.subTest(mode=mode), self.assertRaisesRegex(ValueError, "does not match"):
                metadata.verify_attestation(changed, directory, self.public, OPENSSL)

    @unittest.skipUnless(os.name == "nt", "PowerShell installer verification runs on Windows")
    def test_windows_signing_state_and_version_gate(self):
        subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                        str(Path(__file__).with_name("test_verify_windows.ps1"))], check=True)

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


class WindowsVerifierEnvironmentTests(unittest.TestCase):
    def test_windows_verifier_uses_native_modules_without_changing_parent(self):
        entry = dict(target='windows-x64', file=__file__, version='fixture-version')
        with patch.object(metadata.sys, 'platform', 'win32'), \
                patch.object(metadata.channels, 'parse_version', return_value=('fixture-native-version', 'stable', None)), \
                patch.dict(os.environ, {'PSModulePath': 'foreign-pwsh-modules', 'SystemRoot': 'C:/Windows'}), \
                patch.object(metadata.subprocess, 'run') as child:
            metadata.verify_platform_package(entry)
            self.assertEqual(child.call_args.kwargs['env']['PSModulePath'],
                             str(Path('C:/Windows') / 'System32/WindowsPowerShell/v1.0/Modules'))
            self.assertTrue(child.call_args.kwargs['check'])
            self.assertEqual(os.environ['PSModulePath'], 'foreign-pwsh-modules')


if __name__ == "__main__":
    unittest.main()
