import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import struct
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("windows_signing", Path(__file__).with_name("windows-signing.py"))
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class WindowsSigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.version = signing.product_version()
        self.tag = "v" + self.version
        self.identity = dict(schema=2, platform="windows", repository=signing.REPOSITORY, build_source="local",
                             version=self.version, release_version=self.version, release_tag=self.tag, source_sha="a" * 40, tag_sha="a" * 40)
        self.checks = dict(schema=1, source_sha="a" * 40,
                           checks=[dict(name=n, passed=True) for n in sorted(signing.CHECKS)])

    def inputs(self, destination):
        destination.mkdir(parents=True, exist_ok=True)
        signing.write_json(destination / "context.json", self.identity)
        build = destination / "build"
        build.mkdir(exist_ok=True)
        signing.write_json(build / "build-checks.json", self.checks)
        for name in signing.FILES:
            arch, relative = name.split("/", 1)
            path = build / arch / "Release" / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(name.encode())
        with patch.object(signing, "context", return_value=self.identity):
            signing.stage(destination)
        return destination

    def signed(self, destination):
        self.inputs(destination)
        directory = destination / "signed"
        directory.mkdir()
        names = signing.asset_names(self.version)
        for name in names[:-1:2]:
            (directory / name).write_bytes(("signed bytes: " + name).encode())
            (directory / (name + ".sha256")).write_text(f"{signing.sha256(directory / name)}  {name}\n", encoding="ascii")
        with patch.object(signing, "context", return_value=self.identity), patch.object(signing, "native_verify"), patch.object(signing, "verify_zip"):
            signing.record(destination)
        return directory

    def zip_fixture(self, architecture="x64", signed=True, backslashes=False, wrong_machine=False):
        verifier = signing.load_package_verifier()
        model = self.root / 'model.json'
        model.write_text(json.dumps(dict(canonical_database_sha256=signing.hashlib.sha256(b'database').hexdigest())))
        verifier.MODEL = model
        names = ['KeyKeyTsf_x86.dll', 'KeyKeySettings.exe', 'KeyKeySettingsBackend.dll', 'KeyKeyDeployment.exe',
                 'KeyKeyRegistration_x86.exe', 'WinSparkle.dll']
        if architecture == 'x64':
            names.append('KeyKeyTsf_x64.dll')
        payload = {'Databases/KeyKey.db': b'database', 'LICENSES/OpenVanilla-HanConvert.txt': b'notice',
                   'LICENSES/WinSparkle-LICENSE.txt': b'notice'}
        for name in names:
            data = bytearray(128)
            data[:2] = b'MZ'
            struct.pack_into('<I', data, 0x3c, 0x40)
            data[0x40:0x44] = b'PE\0\0'
            machine = 0x14c if architecture == 'x86' or '_x86' in name else 0x8664
            if wrong_machine and name == 'KeyKeySettings.exe':
                machine = 0x8664 if machine == 0x14c else 0x14c
            struct.pack_into('<H', data, 0x44, machine)
            payload[name] = bytes(data)
        manifest = dict(SchemaVersion=1, Version=self.version, Architecture=architecture, Signed=signed,
                        Files=[dict(Path=n, Sha256=signing.hashlib.sha256(b).hexdigest()) for n, b in payload.items()])
        package = self.root / f'{architecture}-{signed}-{backslashes}-{wrong_machine}.zip'
        with zipfile.ZipFile(package, 'w') as archive:
            entries = {'package/PackageManifest.json': json.dumps(manifest).encode(),
                       'package/README.txt': '新增鍵盤 Windows 10 Windows 11'.encode(),
                       **{'package/Payload/' + name: data for name, data in payload.items()}}
            for name, data in entries.items():
                archive.writestr(name.replace('/', '\\') if backslashes else name, data)
        return package, verifier

    def test_actual_zip_inventory_hash_pe_database_and_windows_separator_checks(self):
        for arch in ('x64', 'x86'):
            for backslashes in (False, True):
                package, verifier = self.zip_fixture(arch, backslashes=backslashes)
                with patch('sys.stdout', new=io.StringIO()):
                    self.assertEqual(verifier.verify(package, require_signed=True)['Architecture'], arch)
            package, verifier = self.zip_fixture(arch, signed=False)
            with self.assertRaisesRegex(AssertionError, 'unsigned ZIP'):
                verifier.verify(package, require_signed=True)
            package, verifier = self.zip_fixture(arch, wrong_machine=True)
            with self.assertRaises(AssertionError):
                verifier.verify(package, require_signed=True)

    def test_zip_native_signatures_are_checked_after_safe_extraction(self):
        package, verifier = self.zip_fixture(backslashes=True)
        def verify(*args):
            folder = Path(args[args.index('-Directory') + 1])
            self.assertEqual(len(list(folder.glob('*.exe'))) + len(list(folder.glob('*.dll'))), 7)
            self.assertEqual(args[args.index('-Architecture') + 1], 'x64')
            raise ValueError('untrusted extracted payload')
        with patch.object(signing, 'load_package_verifier', return_value=verifier), patch.object(signing, 'run', side_effect=verify), \
                patch('sys.stdout', new=io.StringIO()), self.assertRaisesRegex(ValueError, 'untrusted extracted'):
            signing.verify_zip(package, self.version, 'x64')

    def test_workflow_is_check_only_and_artifact_release_pipeline_is_removed(self):
        workflows = signing.ROOT / ".github/workflows"
        text = (workflows / "package-windows.yml").read_text()
        self.assertIn("pull_request:", text)
        self.assertIn("Build-WindowsRelease.ps1", text)
        for forbidden in ("release:\n", "upload-artifact", "contents: write", "WINDOWS_RELEASE_MODE", "release-assets.py"):
            self.assertNotIn(forbidden, text)
        self.assertFalse((workflows / "prepare-windows-signing.yml").exists())
        mirror = (workflows / "mirror-windows-signed.yml").read_text()
        self.assertNotIn("build_run_id", mirror)
        self.assertIn("receipt_sha256", mirror)

    def test_local_prepare_needs_no_ci_or_artifact_access(self):
        with patch.object(signing, "context", return_value=self.identity), patch.object(signing, "api") as api, patch("sys.stdout", new=io.StringIO()):
            signing.prepare(self.tag, self.root / "release")
            api.assert_not_called()
            with self.assertRaisesRegex(ValueError, "already exists"):
                signing.prepare(self.tag, self.root / "release")

    def test_source_must_be_clean_exact_official_tag_and_reviewed_master(self):
        def commands(*args):
            if args[:3] == ("git", "rev-parse", f"refs/tags/{self.tag}^{{commit}}"):
                return "a" * 40
            if args == ("git", "rev-parse", "HEAD"):
                return "a" * 40
            if args[:3] == ("git", "remote", "get-url"):
                return "https://github.com/polobread/KeyKey.git"
            return ""
        with patch.object(signing, "run", side_effect=commands):
            self.assertEqual(signing.context(self.tag), self.identity)
        for bad_command, response in ((("git", "rev-parse", "HEAD"), "b" * 40),
                                      (("git", "ls-files", "--", "keykey-update-private.pem*", "**/keykey-update-private.pem*"), "keykey-update-private.pem.txt"),
                                      (("git", "status", "--porcelain", "--untracked-files=normal"), " M source.cpp"),
                                      (("git", "remote", "get-url", "origin"), "https://github.com/other/fork.git")):
            with self.subTest(command=bad_command), \
                    patch.object(signing, "run", side_effect=lambda *args: response if args == bad_command else commands(*args)):
                with self.assertRaises(ValueError):
                    signing.context(self.tag)
        def unreviewed(*args):
            if args[:3] == ("git", "merge-base", "--is-ancestor"):
                raise ValueError("unreviewed source")
            return commands(*args)
        with patch.object(signing, "run", side_effect=unreviewed), self.assertRaisesRegex(ValueError, "unreviewed"):
            signing.context(self.tag)

    def test_all_local_checks_and_their_source_must_match(self):
        signing.verify_checks(self.checks, self.identity)
        for broken in (dict(self.checks, source_sha="b" * 40),
                       dict(self.checks, checks=self.checks["checks"][:-1]),
                       dict(self.checks, checks=[dict(c, passed=False) for c in self.checks["checks"]])):
            with self.assertRaises(ValueError):
                signing.verify_checks(broken, self.identity)

    def test_stage_snapshots_both_architecture_runtimes_and_rejects_changes(self):
        destination = self.inputs(self.root / "release")
        with patch.object(signing, "context", return_value=self.identity):
            self.assertEqual(signing.verify_built(destination), self.identity)
            (destination / "inputs/x86/KeyKeySettings.exe").write_bytes(b"tampered x86 settings")
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                signing.verify_built(destination)

    def test_seven_assets_and_checksums_bind_exe_and_both_zips(self):
        directory = self.signed(self.root / "release")
        paths = signing.verify_signed(directory, self.identity)
        self.assertEqual(len(paths), 7)
        self.assertTrue(all(".unsigned" not in p.name for p in paths))
        self.assertEqual(paths[-1].name, f"chichi77-KeyKey-{self.version}-windows-build-info.json")
        for index in (0, 2, 4):
            original = paths[index].read_bytes()
            paths[index].write_bytes(b"changed after signing")
            with self.subTest(asset=paths[index].name), self.assertRaisesRegex(ValueError, "hash mismatch"):
                signing.verify_signed(directory, self.identity)
            paths[index].write_bytes(original)

    def test_record_requires_native_exe_and_actual_zip_signature_verification(self):
        directory = self.signed(self.root / "release")
        info = directory / signing.asset_names(self.version)[-1]
        info.unlink()
        with patch.object(signing, "context", return_value=self.identity), patch.object(signing, "native_verify") as native, \
                patch.object(signing, "verify_zip", side_effect=ValueError("unsigned ZIP payload")):
            with self.assertRaisesRegex(ValueError, "unsigned ZIP"):
                signing.record(directory.parent)
            native.assert_called_once()
            self.assertFalse(info.exists())

    def test_checksum_cannot_be_rewritten_to_describe_wrong_payload(self):
        directory = self.signed(self.root / "release")
        name = signing.asset_names(self.version)[1]
        (directory / name).write_text("0" * 64 + "  other.exe\n")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            signing.verify_signed(directory, self.identity)

    def test_publish_binds_entire_build_info_and_verifies_all_signatures_before_upload(self):
        destination = self.root / "release"
        directory = self.signed(destination)
        info = directory / signing.asset_names(self.version)[-1]
        with patch.object(signing, "context", return_value=self.identity), patch.object(signing, "verify_native_assets") as native, \
                patch.object(signing, "release_assets") as assets:
            with self.assertRaisesRegex(ValueError, "approved build-info"):
                signing.publish(self.tag, destination, "0" * 64)
            native.assert_not_called()
            native.side_effect = ValueError("untrusted ZIP signature")
            with self.assertRaisesRegex(ValueError, "untrusted ZIP"):
                signing.publish(self.tag, destination, signing.sha256(info))
            assets.assert_not_called()

    def test_collision_in_any_zip_prevents_all_uploads_and_mirror_dispatch(self):
        destination = self.root / "release"
        directory = self.signed(destination)
        info = directory / signing.asset_names(self.version)[-1]
        def download(tag, name, output):
            (Path(output) / name).write_bytes(b"existing other ZIP")
        with patch.object(signing, "context", return_value=self.identity), patch.object(signing, "verify_native_assets"), \
                patch.object(signing, "release_assets", return_value={signing.asset_names(self.version)[4]: {}}), \
                patch.object(signing, "download_asset", side_effect=download), patch.object(signing, "run") as run:
            with self.assertRaisesRegex(ValueError, "refusing overwrite"):
                signing.publish(self.tag, destination, signing.sha256(info))
            run.assert_not_called()

    def test_publish_uploads_all_seven_reads_back_and_requests_mirror_without_ci_run(self):
        destination = self.root / "release"
        directory = self.signed(destination)
        info = directory / signing.asset_names(self.version)[-1]
        def download(tag, name, output):
            (Path(output) / name).write_bytes((directory / name).read_bytes())
        with patch.object(signing, "context", return_value=self.identity), patch.object(signing, "verify_native_assets"), \
                patch.object(signing, "release_assets", return_value={}), patch.object(signing, "download_asset", side_effect=download), \
                patch.object(signing, "run") as run, patch("sys.stdout", new=io.StringIO()):
            signing.publish(self.tag, destination, signing.sha256(info))
        calls = [c.args for c in run.call_args_list]
        self.assertEqual(sum(c[:3] == ("gh", "release", "upload") for c in calls), 7)
        self.assertTrue(all("--clobber" not in c for c in calls))
        self.assertIn("receipt_sha256=" + signing.sha256(info), calls[-1])
        self.assertNotIn("build_run_id", str(calls[-1]))

    def test_mirror_adds_all_seven_with_conditional_writes_and_readbacks(self):
        directory = self.signed(self.root / "release")
        info = directory / signing.asset_names(self.version)[-1]
        def aws(*args):
            if args[:3] == ("aws", "s3api", "get-object"):
                Path(args[-1]).write_bytes((directory / Path(args[-1]).name).read_bytes())
            return json.dumps(dict(Invalidation=dict(Id="EXAMPLE")))
        env = dict(RELEASE_MIRROR_BUCKET="example-bucket", RELEASE_MIRROR_DISTRIBUTION_ID="EXAMPLE", RELEASE_MIRROR_BASE_URL="https://cdn.example.invalid")
        with patch.dict(os.environ, env), patch.object(signing, "context", return_value=self.identity), \
                patch.object(signing, "verify_zip"), patch.object(signing, "run", side_effect=aws), patch.object(signing, "verify_url") as cdn, \
                patch.object(signing.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as put, patch("sys.stdout", new=io.StringIO()):
            signing.mirror(self.tag, directory, signing.sha256(info))
        self.assertEqual(put.call_count, 7)
        self.assertEqual(cdn.call_count, 7)
        for call in put.call_args_list:
            self.assertIn("--if-none-match", call.args[0])
            self.assertEqual(call.args[0][call.args[0].index("--if-none-match") + 1], "*")


if __name__ == "__main__":
    unittest.main()
