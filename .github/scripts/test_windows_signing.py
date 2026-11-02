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
        self.base_identity = dict(schema=3, platform="windows", repository=signing.REPOSITORY, workflow=signing.WORKFLOW, build_source="actions",
                             version=self.version, release_version=self.version, release_tag=self.tag, source_sha="a" * 40, tag_sha="a" * 40)
        self.identity = dict(self.base_identity, run_id=101, run_attempt=1, artifact_id=202, artifact_digest="sha256:" + "0" * 64)
        self.checks = dict(schema=1, source_sha="a" * 40,
                           checks=[dict(name=n, passed=True) for n in sorted(signing.CHECKS)],
                           test_results={arch: [dict(name="isolated", status="passed")] for arch in ("x64", "x86")})

    def inputs(self, destination):
        build = destination.with_name(destination.name + "-build")
        build.mkdir(parents=True)
        signing.write_json(build / "build-checks.json", self.checks)
        signing.write_json(build / "update-config.json", dict(release_version=self.version, update_channel="stable"))
        for name in signing.FILES:
            arch, relative = name.split("/", 1)
            path = build / arch / ("" if relative.startswith("guanyinma/") else "Release") / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(name.encode())
        unsigned = build / "unsigned"
        unsigned.mkdir()
        for name in signing.unsigned_names(self.version):
            (unsigned / name).write_bytes(name.encode())
        env = dict(GITHUB_ACTIONS="true", GITHUB_REPOSITORY=signing.REPOSITORY, GITHUB_RUN_ID="101", GITHUB_RUN_ATTEMPT="1")
        with patch.dict(os.environ, env), patch.object(signing, "run", side_effect=lambda *args: "a" * 40 if args[1:3] == ("rev-parse", "HEAD") else ""):
            signing.stage(destination, build, self.tag)
        archive = destination.with_suffix(".zip")
        with zipfile.ZipFile(archive, "w") as bundle:
            for path in destination.rglob("*"):
                if path.is_file():
                    bundle.write(path, path.relative_to(destination).as_posix())
        (destination / "inputs.zip").write_bytes(archive.read_bytes())
        self.identity = dict(self.identity, artifact_digest="sha256:" + signing.sha256(archive))
        signing.write_json(destination / "context.json", self.identity)
        return destination

    def signed(self, destination):
        self.inputs(destination)
        directory = destination / "signed"
        directory.mkdir()
        names = signing.asset_names(self.version)
        for name in names[:-1:2]:
            (directory / name).write_bytes(("signed bytes: " + name).encode())
            (directory / (name + ".sha256")).write_text(f"{signing.sha256(directory / name)}  {name}\n", encoding="ascii")
        with patch.object(signing, "context", return_value=self.identity), patch.object(signing, "provenance", side_effect=lambda *a, **k: self.identity), patch.object(signing, "native_verify"), patch.object(signing, "verify_zip"):
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
        with patch.object(signing.sys, 'platform', 'win32'), \
                patch.object(signing, 'load_package_verifier', return_value=verifier), patch.object(signing, 'run', side_effect=verify), \
                patch('sys.stdout', new=io.StringIO()), self.assertRaisesRegex(ValueError, 'untrusted extracted'):
            signing.verify_zip(package, self.version, 'x64')

    def test_windows_powershell_does_not_inherit_pwsh_modules(self):
        completed = subprocess.CompletedProcess([], 0, stdout=b'', stderr=b'')
        with patch.dict(os.environ, {'PSModulePath': 'foreign-pwsh-modules', 'SystemRoot': str(self.root)}), \
                patch.object(signing.subprocess, 'run', return_value=completed) as child:
            signing.run('powershell.exe', '-NoProfile')
            environment = child.call_args.kwargs['env']
            self.assertEqual(environment['PSModulePath'], str(self.root / 'System32/WindowsPowerShell/v1.0/Modules'))
            self.assertEqual(os.environ['PSModulePath'], 'foreign-pwsh-modules')
            signing.run('git', 'status')
            self.assertIsNone(child.call_args.kwargs['env'])

    def test_workflow_shares_build_script_and_only_uploads_unsigned_inputs(self):
        workflows = signing.ROOT / ".github/workflows"
        text = (workflows / "package-windows.yml").read_text()
        self.assertIn("pull_request:", text)
        self.assertIn("Build-WindowsRelease.ps1", text)
        for forbidden in ("release:\n", "contents: write", "WINDOWS_RELEASE_MODE", "release-assets.py"):
            self.assertNotIn(forbidden, text)
        self.assertIn('actions/upload-artifact@', text)
        self.assertIn("github.event_name != 'pull_request'", text)
        self.assertIn('keykey-windows-unsigned-', text)
        self.assertFalse((workflows / "prepare-windows-signing.yml").exists())
        mirror = (workflows / "mirror-windows-signed.yml").read_text()
        self.assertNotIn("build_run_id", mirror)
        self.assertIn("receipt_sha256", mirror)

    def test_mirror_verifies_tag_bytes_with_reviewed_master_mirror_tools(self):
        workflow = (signing.ROOT / ".github/workflows/mirror-windows-signed.yml").read_text()
        verify, mirror = workflow.split("\n  mirror:\n", 1)
        self.assertIn("github.ref == 'refs/heads/master'", verify)
        self.assertIn("ref: ${{ inputs.release_tag }}", verify)
        self.assertNotIn("ref: ${{ github.sha }}", verify)
        self.assertIn("ref: ${{ github.sha }}", mirror)
        self.assertNotIn("ref: ${{ inputs.release_tag }}", mirror)
        self.assertIn("needs: verify", mirror)
        self.assertIn("environment: release", mirror)
        self.assertIn("id-token: write", mirror)

    def test_shared_staging_needs_no_release_tag_or_api_access(self):
        with patch.object(signing, "api") as api:
            destination = self.inputs(self.root / "release")
            api.assert_not_called()
        self.assertEqual(set(signing.read_json(destination / "signing-inputs.json")["files"]), signing.bundle_files(self.version))
        self.assertFalse(any("private" in str(p.relative_to(destination)) for p in destination.rglob("*")))

    def test_ci_provenance_rejects_untrusted_run_ref_source_and_artifact(self):
        record = dict(status="completed", conclusion="success", repository=dict(full_name=signing.REPOSITORY),
                      head_repository=dict(full_name=signing.REPOSITORY), event="push", head_branch="master",
                      workflow_id=1, head_sha="a" * 40, run_attempt=1)
        artifact = dict(id=202, name=signing.artifact_name(101, 1), expired=False,
                        workflow_run=dict(head_sha="a" * 40), digest="sha256:" + "1" * 64)
        def api(endpoint):
            if endpoint.endswith('/artifacts?per_page=100'):
                return dict(total_count=1, artifacts=[artifact])
            if endpoint == 'actions/workflows/1':
                return dict(path=signing.WORKFLOW)
            return record
        with patch.object(signing, "api", side_effect=api), patch.object(signing, "context", return_value=self.base_identity):
            self.assertEqual(signing.provenance(101, self.tag)["artifact_id"], 202)
            for field, value in (("event", "pull_request"), ("conclusion", "failure"),
                                 ("head_branch", "unreviewed"), ("head_sha", "b" * 40),
                                 ("head_repository", dict(full_name="other/fork")), ("run_attempt", 2)):
                original = record[field]
                record[field] = value
                with self.subTest(field=field), self.assertRaises(ValueError):
                    signing.provenance(101, self.tag)
                record[field] = original
            for field, value in (("expired", True), ("digest", None), ("workflow_run", dict(head_sha="b" * 40))):
                original = artifact[field]
                artifact[field] = value
                with self.subTest(field=field), self.assertRaises(ValueError):
                    signing.provenance(101, self.tag)
                artifact[field] = original

    def test_artifact_allowlist_rejects_private_paths_traversal_and_duplicates(self):
        destination = self.inputs(self.root / "release")
        original = (destination / "inputs.zip").read_bytes()
        for name in ('../outside', 'keykey-update-private.pem', 'signing-inputs.json'):
            archive = self.root / "bad.zip"
            archive.write_bytes(original)
            with zipfile.ZipFile(archive, 'a') as bundle:
                bundle.writestr(name, b'synthetic extra entry')
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'Unexpected/duplicate'):
                signing.extract(archive, self.root / "extracted", self.version)
        self.assertFalse((self.root / "extracted").exists())

    def test_download_rejects_wrong_digest_before_extracting(self):
        identity = dict(self.identity, artifact_digest='sha256:' + '1' * 64)
        def download(command, **kwargs):
            kwargs['stdout'].write(b'wrong archive bytes')
            return subprocess.CompletedProcess(command, 0)
        with patch.object(signing, 'provenance', return_value=identity), patch.object(signing.subprocess, 'run', side_effect=download):
            with self.assertRaisesRegex(ValueError, 'digest mismatch'):
                signing.download(101, self.tag, self.root / 'download')
        self.assertFalse((self.root / 'download/inputs').exists())

    def test_download_cache_is_verified_without_redownloading_or_building(self):
        fixture = self.inputs(self.root / 'fixture')
        data = (fixture / 'inputs.zip').read_bytes()
        def download(command, **kwargs):
            self.assertEqual(command[:2], ['gh', 'api'])
            kwargs['stdout'].write(data)
            return subprocess.CompletedProcess(command, 0)
        with patch.object(signing, 'provenance', side_effect=lambda *a, **k: self.identity), \
                patch.object(signing, 'context', return_value=self.base_identity), \
                patch.object(signing.subprocess, 'run', side_effect=download) as request, patch('sys.stdout', new=io.StringIO()):
            destination = self.root / 'download'
            signing.download(101, self.tag, destination)
            signing.download(101, self.tag, destination)
            self.assertEqual(request.call_count, 1)
            (destination / 'inputs/x64/KeyKeyTsf.dll').write_bytes(b'tampered')
            with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                signing.download(101, self.tag, destination)
            self.assertEqual(request.call_count, 1)

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
            self.assertEqual(signing.context(self.tag), self.base_identity)
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
        for broken in (dict(self.checks, source_sha="b" * 40), dict(self.checks, test_results={}),
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
        with patch.object(signing, "context", return_value=self.identity), patch.object(signing, "provenance", side_effect=lambda *a, **k: self.identity), patch.object(signing, "native_verify") as native, \
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
        with patch.object(signing, "context", return_value=self.identity), patch.object(signing, "provenance", side_effect=lambda *a, **k: self.identity), patch.object(signing, "verify_native_assets") as native, \
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
        with patch.object(signing, "context", return_value=self.identity), patch.object(signing, "provenance", side_effect=lambda *a, **k: self.identity), patch.object(signing, "verify_native_assets"), \
                patch.object(signing, "release_assets", return_value={signing.asset_names(self.version)[4]: {}}), \
                patch.object(signing, "download_asset", side_effect=download), patch.object(signing, "run") as run:
            with self.assertRaisesRegex(ValueError, "refusing overwrite"):
                signing.publish(self.tag, destination, signing.sha256(info))
            run.assert_not_called()

    def test_publish_uploads_all_seven_reads_back_and_requests_mirror(self):
        destination = self.root / "release"
        directory = self.signed(destination)
        info = directory / signing.asset_names(self.version)[-1]
        def download(tag, name, output):
            (Path(output) / name).write_bytes((directory / name).read_bytes())
        with patch.object(signing, "context", return_value=self.identity), patch.object(signing, "provenance", side_effect=lambda *a, **k: self.identity), patch.object(signing, "verify_native_assets"), \
                patch.object(signing, "release_assets", return_value={}), patch.object(signing, "download_asset", side_effect=download), \
                patch.object(signing, "run") as run, patch("sys.stdout", new=io.StringIO()):
            signing.publish(self.tag, destination, signing.sha256(info))
        calls = [c.args for c in run.call_args_list]
        self.assertEqual(sum(c[:3] == ("gh", "release", "upload") for c in calls), 7)
        self.assertTrue(all("--clobber" not in c for c in calls))
        self.assertIn("receipt_sha256=" + signing.sha256(info), calls[-1])
        self.assertNotIn("build_run_id", str(calls[-1]))

    def test_mirror_adds_seven_assets_and_optional_verified_update_copy(self):
        directory = self.signed(self.root / "release")
        info = directory / signing.asset_names(self.version)[-1]
        installer = directory / signing.asset_names(self.version)[0]
        checksum = signing.sha256(installer)
        copy_name = f"KeyKey-{self.version}-windows-x64-{checksum}.exe"
        def aws(*args):
            if args[:3] == ("aws", "s3api", "get-object"):
                name = Path(args[-1]).name
                source = installer if name == copy_name else directory / name
                Path(args[-1]).write_bytes(source.read_bytes())
            return json.dumps(dict(Invalidation=dict(Id="EXAMPLE")))
        def download(tag, name, output):
            self.assertEqual((tag, name), (self.tag, copy_name))
            (Path(output) / name).write_bytes(installer.read_bytes())
        env = dict(RELEASE_MIRROR_BUCKET="example-bucket", RELEASE_MIRROR_DISTRIBUTION_ID="EXAMPLE", RELEASE_MIRROR_BASE_URL="https://cdn.example.invalid")
        for include_copy in (False, True):
            assets = {"unrelated-macos-asset.pkg.zip": {}}
            if include_copy:
                assets[copy_name] = dict(size=installer.stat().st_size, digest="sha256:" + checksum)
            with self.subTest(copy=include_copy), patch.dict(os.environ, env), patch.object(signing, "context", return_value=self.identity), \
                    patch.object(signing, "verify_zip"), patch.object(signing, "release_assets", return_value=assets), \
                    patch.object(signing, "download_asset", side_effect=download) as fetched, \
                    patch.object(signing, "run", side_effect=aws) as requests, patch.object(signing, "verify_url") as cdn, \
                    patch.object(signing.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as put, \
                    patch("sys.stdout", new=io.StringIO()):
                signing.mirror(self.tag, directory, signing.sha256(info))
            self.assertEqual(put.call_count, 7 + include_copy)
            self.assertEqual(cdn.call_count, 7 + include_copy)
            self.assertEqual(fetched.call_count, int(include_copy))
            expected = set(signing.asset_names(self.version)) | ({copy_name} if include_copy else set())
            self.assertEqual({call.args[0].rsplit('/', 1)[-1] for call in cdn.call_args_list}, expected)
            invalidation = next(call.args for call in requests.call_args_list if call.args[:3] == ("aws", "cloudfront", "create-invalidation"))
            start = invalidation.index("--paths") + 1
            self.assertEqual(set(invalidation[start:invalidation.index("--no-cli-pager")]),
                             {f"/keykey/releases/download/{self.tag}/{name}" for name in expected})
            for call in put.call_args_list:
                command = call.args[0]
                self.assertIn("--if-none-match", command)
                self.assertEqual(command[command.index("--if-none-match") + 1], "*")
                if command[command.index("--key") + 1].endswith("/" + copy_name):
                    self.assertEqual(command[command.index("--body") + 1], str(installer))
            self.assertFalse((directory / copy_name).exists())

    def test_mirror_rejects_wrong_update_copies_before_any_aws_write(self):
        directory = self.signed(self.root / "release")
        info = directory / signing.asset_names(self.version)[-1]
        installer = directory / signing.asset_names(self.version)[0]
        payload = installer.read_bytes()
        checksum = signing.sha256(installer)
        prefix = f"KeyKey-{self.version}-windows-x64-"
        name = f"{prefix}{checksum}.exe"
        valid = dict(size=len(payload), digest="sha256:" + checksum)
        cases = (
            ("extra copy", {name: valid, prefix + "0" * 64 + ".exe": valid}, payload),
            ("wrong name", {prefix + "0" * 64 + ".exe": valid}, payload),
            ("wrong declared hash", {name: dict(valid, digest="sha256:" + "0" * 64)}, payload),
            ("wrong declared size", {name: dict(valid, size=len(payload) + 1)}, payload),
            ("wrong downloaded hash", {name: valid}, bytes(byte ^ 1 for byte in payload)),
            ("wrong downloaded size", {name: valid}, payload + b"extra"),
        )
        for label, assets, downloaded in cases:
            def download(tag, filename, output):
                (Path(output) / filename).write_bytes(downloaded)
            with self.subTest(case=label), patch.object(signing, "context", return_value=self.identity), \
                    patch.object(signing, "verify_zip"), patch.object(signing, "release_assets", return_value=assets), \
                    patch.object(signing, "download_asset", side_effect=download), patch.object(signing, "run") as requests, \
                    patch.object(signing.subprocess, "run") as put, patch.object(signing, "verify_url") as cdn:
                with self.assertRaisesRegex(ValueError, "update copy"):
                    signing.mirror(self.tag, directory, signing.sha256(info))
                put.assert_not_called()
                requests.assert_not_called()
                cdn.assert_not_called()


if __name__ == "__main__":
    unittest.main()
