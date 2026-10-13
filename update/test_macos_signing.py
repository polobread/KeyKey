import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("macos_signing", ROOT / "update/sign-macos.py")
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)
DEBUG = signing.DEBUG_ENTITLEMENT
RUNTIME = {"com.apple.security.app-sandbox": True,
           "com.apple.security.application-groups": ["io.github.polobread.keykey.test"],
           "com.apple.security.network.client": True}


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / "Test.app"
        self.binary = self.app / "Contents/MacOS/Test"
        self.binary.parent.mkdir(parents=True)
        self.binary.write_bytes(b"\xcf\xfa\xed\xfe" + bytes(28))

    def test_targets_are_inside_out_and_skip_symlinks_and_resources(self):
        helper = self.app / "Contents/SharedSupport/Helper.app"
        executable = helper / "Contents/MacOS/Helper"
        executable.parent.mkdir(parents=True)
        executable.write_bytes(self.binary.read_bytes())
        (helper / "alias").symlink_to(executable)
        (self.app / "Contents/notes.txt").write_text("not executable")
        targets = signing.signing_targets(self.app)
        self.assertEqual(set(targets), {self.binary, executable, helper, self.app})
        self.assertLess(targets.index(executable), targets.index(helper))
        self.assertEqual(targets[-1], self.app)

    def test_unsigned_binary_is_allowed_only_before_signing(self):
        result = subprocess.CompletedProcess([], 1, b"", b"test: code object is not signed at all")
        with patch.object(signing.subprocess, "run", return_value=result):
            self.assertEqual(signing.read_entitlements(self.binary, allow_unsigned=True), {})
            with self.assertRaisesRegex(ValueError, "Cannot read entitlements"):
                signing.read_entitlements(self.binary)

    def test_unknown_extraction_failure_is_not_treated_as_unsigned(self):
        result = subprocess.CompletedProcess([], 1, b"", b"invalid signature")
        with patch.object(signing.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(ValueError, "Cannot read entitlements"):
                signing.read_entitlements(self.binary, allow_unsigned=True)

    def test_empty_xml_and_binary_plists(self):
        for value in ({}, RUNTIME):
            for fmt in (plistlib.FMT_XML, plistlib.FMT_BINARY):
                result = subprocess.CompletedProcess([], 0, plistlib.dumps(value, fmt=fmt), b"")
                with patch.object(signing.subprocess, "run", return_value=result):
                    self.assertEqual(signing.read_entitlements(self.binary), value)
        with patch.object(signing.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, b"", b"")):
            self.assertEqual(signing.read_entitlements(self.binary), {})

    def test_malformed_or_non_dictionary_entitlements_fail_closed(self):
        for blob in (b"bad plist", b'<?xml version="1.0"?><plist><dict>', plistlib.dumps(["not a dictionary"])):
            with patch.object(signing.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, blob, b"")):
                with self.assertRaises(ValueError):
                    signing.read_entitlements(self.binary)

    def test_removes_only_debug_access_across_both_slices(self):
        first = dict(RUNTIME, **{DEBUG: True})
        second = dict(RUNTIME, **{DEBUG: False})
        with patch.object(signing, "architectures", return_value=["arm64", "x86_64"]), \
             patch.object(signing, "read_entitlements", side_effect=[first, second]) as read:
            self.assertEqual(signing.distribution_entitlements(self.binary), RUNTIME)
            self.assertEqual([call.args[1] for call in read.call_args_list], ["arm64", "x86_64"])

    def test_different_runtime_permissions_across_slices_are_rejected(self):
        with patch.object(signing, "architectures", return_value=["arm64", "x86_64"]), \
             patch.object(signing, "read_entitlements", side_effect=[RUNTIME, {}]):
            with self.assertRaisesRegex(ValueError, "Different runtime entitlements"):
                signing.distribution_entitlements(self.binary)

    def test_explicit_entitlements_and_runtime_timestamp_and_cleanup(self):
        commands = []

        def codesign(command, **kwargs):
            commands.append(command)
            if "--force" in command:
                path = Path(command[command.index("--entitlements") + 1])
                self.assertEqual(plistlib.loads(path.read_bytes()), RUNTIME)
            return subprocess.CompletedProcess(command, 0)

        with patch.object(signing, "distribution_entitlements", return_value=RUNTIME), \
             patch.object(signing, "architectures", return_value=["arm64"]), \
             patch.object(signing, "read_entitlements", return_value=RUNTIME), \
             patch.object(signing.subprocess, "run", side_effect=codesign), \
             patch.object(signing, "verify") as verify:
            signing.sign(self.app, "Developer ID Application: TEST")
            verify.assert_called_once_with(self.app)
        self.assertEqual(len(commands), 2)
        for command in commands:
            self.assertNotIn("--preserve-metadata=entitlements", command)
            self.assertIn("runtime", command)
            self.assertIn("--timestamp", command)
            self.assertIn("--force-library-entitlements", command)
            self.assertFalse(Path(command[command.index("--entitlements") + 1]).exists())

    def test_ad_hoc_signing_uses_explicit_empty_plist_without_timestamp(self):
        def codesign(command, **kwargs):
            self.assertNotIn("--timestamp", command)
            self.assertNotIn("--options", command)
            self.assertEqual(plistlib.loads(Path(command[command.index("--entitlements") + 1]).read_bytes()), {})
            return subprocess.CompletedProcess(command, 0)

        with patch.object(signing, "distribution_entitlements", return_value={}), \
             patch.object(signing, "architectures", return_value=["arm64"]), \
             patch.object(signing, "read_entitlements", return_value={}), \
             patch.object(signing.subprocess, "run", side_effect=codesign), patch.object(signing, "verify"):
            signing.sign(self.app, "-")

    def test_post_sign_permission_change_aborts(self):
        with patch.object(signing, "distribution_entitlements", return_value=RUNTIME), \
             patch.object(signing, "architectures", return_value=["arm64"]), \
             patch.object(signing, "read_entitlements", return_value={}), \
             patch.object(signing.subprocess, "run"), patch.object(signing, "verify") as verify:
            with self.assertRaisesRegex(ValueError, "Entitlements changed"):
                signing.sign(self.app, "-")
            verify.assert_not_called()

    def test_verification_checks_non_native_slice_and_rejects_debug_key(self):
        with patch.object(signing.subprocess, "run") as run, \
             patch.object(signing, "architectures", return_value=["arm64", "x86_64"]), \
             patch.object(signing, "read_entitlements", side_effect=[{}, {DEBUG: True}]):
            with self.assertRaisesRegex(ValueError, "x86_64"):
                signing.verify(self.app)
            self.assertIn("--all-architectures", run.call_args.args[0])

    def test_release_config_disables_debug_injection_without_changing_debug(self):
        config = (ROOT / "Source/Takao-macOS.xcconfig").read_text()
        self.assertIn("CODE_SIGN_INJECT_BASE_ENTITLEMENTS[config=Release] = NO", config)
        self.assertNotIn("CODE_SIGN_INJECT_BASE_ENTITLEMENTS[config=Debug] = NO", config)


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcrun"), "macOS codesign/clang integration")
class NativeSigningTests(unittest.TestCase):
    @unittest.skipUnless((ROOT / "update/.cache/macos-2.10.0/Sparkle.framework").is_dir(), "cached Sparkle SDK required")
    def test_real_sparkle_helpers_keep_every_runtime_entitlement(self):
        with tempfile.TemporaryDirectory(prefix="keykey-sparkle-sign-test-") as scratch:
            root = Path(scratch)
            app = root / "Test.app"
            executable = app / "Contents/MacOS/Test"
            executable.parent.mkdir(parents=True)
            source = root / "main.c"
            source.write_text("int main(void) { return 0; }\n")
            subprocess.run(["xcrun", "clang", "-arch", "arm64", "-mmacosx-version-min=15.0",
                            str(source), "-o", str(executable)], check=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps(dict(
                CFBundleExecutable="Test", CFBundleIdentifier="test.keykey.sparkle",
                CFBundlePackageType="APPL", CFBundleVersion="1.3.2")))
            shutil.copytree(ROOT / "update/.cache/macos-2.10.0/Sparkle.framework",
                            app / "Contents/Frameworks/Sparkle.framework", symlinks=True)
            expected = {path: signing.distribution_entitlements(path) for path in signing.signing_targets(app)}
            # Vendor helpers do not all use sandbox entitlements. Compare the
            # complete actual dictionaries, including Autoupdate's identifier;
            # the universal fixture above covers sandbox/XPC key preservation.
            self.assertTrue(any(expected.values()))
            self.assertTrue(any(path.name == "Downloader" for path in expected))
            self.assertTrue(any(path.name == "Installer" for path in expected))
            signing.sign(app, "-")
            for path, entitlements in expected.items():
                for architecture in signing.architectures(path):
                    self.assertEqual(signing.read_entitlements(path, architecture), entitlements)

    def test_real_nested_universal_binaries_remove_debug_preserve_runtime_permissions(self):
        # All code and test entitlements stay in a temporary directory. Never
        # launch an input method, use a private identity, or submit to Apple.
        with tempfile.TemporaryDirectory(prefix="keykey-sign-test-") as scratch:
            root = Path(scratch)
            source = root / "main.c"
            source.write_text("int main(void) { return 0; }\n")
            fixture = root / "fixture"
            subprocess.run(["xcrun", "clang", "-arch", "arm64", "-arch", "x86_64",
                            "-mmacosx-version-min=15.0", str(source), "-o", str(fixture)], check=True)
            app = root / "Test.app"
            bundles = [app, *[app / "Contents/SharedSupport" / f"{name}.app"
                              for name in ("InstallerHelp", "PhraseEditor", "Preferences")],
                       app / "Contents/Frameworks/Test.framework/Versions/A/XPCServices/Test.xpc"]
            for index, bundle in enumerate(bundles):
                executable = bundle / "Contents/MacOS/Test"
                executable.parent.mkdir(parents=True)
                shutil.copyfile(fixture, executable)
                executable.chmod(0o755)
                (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(dict(
                    CFBundleExecutable="Test", CFBundleIdentifier=f"test.keykey.signing{index}",
                    CFBundlePackageType="XPC!" if bundle.suffix == ".xpc" else "APPL",
                    CFBundleVersion="1.3.2")))
            framework = app / "Contents/Frameworks/Test.framework"
            resources = framework / "Versions/A/Resources"
            resources.mkdir()
            (resources / "Info.plist").write_bytes(plistlib.dumps(dict(
                CFBundleExecutable="Test", CFBundleIdentifier="test.keykey.framework",
                CFBundlePackageType="FMWK", CFBundleVersion="1.3.2")))
            subprocess.run(["xcrun", "clang", "-dynamiclib", "-arch", "arm64", "-arch", "x86_64",
                            "-mmacosx-version-min=15.0", str(source), "-o", str(framework / "Versions/A/Test")], check=True)
            (framework / "Versions/Current").symlink_to("A")
            (framework / "Test").symlink_to("Versions/Current/Test")
            (framework / "Resources").symlink_to("Versions/Current/Resources")
            debug_plist = root / "debug.plist"
            debug_plist.write_bytes(plistlib.dumps(dict(RUNTIME, **{DEBUG: True})))
            for path in signing.signing_targets(app):
                subprocess.run(["codesign", "--force", "--sign", "-", "--entitlements",
                                str(debug_plist), "--force-library-entitlements", str(path)], check=True)
            with self.assertRaisesRegex(ValueError, DEBUG):
                signing.verify(app)
            signing.sign(app, "-")
            for path in signing.signing_targets(app):
                for architecture in signing.architectures(path):
                    self.assertEqual(signing.read_entitlements(path, architecture), RUNTIME)


if __name__ == "__main__":
    unittest.main()
