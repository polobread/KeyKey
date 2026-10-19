from contextlib import nullcontext
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
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
        self.context = dict(schema=1, repository=signing.REPOSITORY, workflow=signing.WORKFLOW,
                            version="1.3.3", release_tag="v1.3.3", source_sha="a" * 40,
                            tag_sha="a" * 40, run_id=123, run_attempt=1, artifact_id=9,
                            artifact_digest="sha256:" + "b" * 64)

    def bundle(self, directory):
        directory.mkdir(parents=True, exist_ok=True)
        hashes = {}
        for name in signing.FILES:
            path = directory / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(name.encode())
            hashes[name] = signing.sha256(path)
        manifest = {k: self.context[k] for k in ("schema", "repository", "workflow", "version", "source_sha",
                                               "release_tag", "run_id", "run_attempt")}
        manifest["files"] = hashes
        signing.write_json(directory / "signing-inputs.json", manifest)
        return manifest

    def archive(self, directory, target):
        with zipfile.ZipFile(target, "w") as archive:
            for path in directory.rglob("*"):
                if path.is_file():
                    archive.write(path, path.relative_to(directory).as_posix())

    def signed(self, directory):
        directory.mkdir(parents=True, exist_ok=True)
        installer, checksum, info = signing.asset_names("1.3.3")
        (directory / installer).write_bytes(b"simulated-signed-installer")
        digest = signing.sha256(directory / installer)
        (directory / checksum).write_text(f"{digest}  {installer}\n", encoding="ascii")
        signing.write_json(directory / info, dict(self.context, windows_signing="authenticode",
                                                 installer=installer, sha256=digest))
        return directory / installer

    def test_unsigned_fallback_is_preserved_and_modes_are_mutually_exclusive(self):
        workflows = signing.ROOT / '.github/workflows'
        legacy = (workflows / 'package-windows.yml').read_text(encoding='utf-8')
        prepared = (workflows / 'prepare-windows-signing.yml').read_text(encoding='utf-8')
        def modes(workflow):
            job = workflow.split('  package:\n', 1)[1].split('    runs-on:', 1)[0]
            condition = next(line.strip()[4:] for line in job.splitlines() if line.strip().startswith('if: '))
            clauses = condition.split(' || ')
            values = []
            for clause in clauses:
                match = signing.re.fullmatch(r"vars\.WINDOWS_RELEASE_MODE == '([^']*)'", clause)
                self.assertIsNotNone(match, 'Release mode gate must remain an explicit allowlist')
                values.append(match[1])
            return values
        unsigned_modes, certum_modes = modes(legacy), modes(prepared)
        for mode, expected in (('', (False, True)), ('certum', (False, True)),
                               ('unsigned', (True, False)), ('typo', (False, False))):
            self.assertEqual((mode in unsigned_modes, mode in certum_modes), expected)
        for step in ('Build unsigned installer archive', 'Build unsigned NSIS installer',
                     'Verify actual ZIP contents', 'Publish unsigned Windows assets to the GitHub Release',
                     'Mirror the verified Windows assets to S3'):
            self.assertIn(f'- name: {step}', legacy)
        self.assertNotIn('windows-signing.py stage', legacy)
        self.assertIn('windows-signing.py stage', prepared)
        self.assertNotIn('release-assets.py publish', prepared)
        self.assertEqual(signing.WORKFLOW, '.github/workflows/prepare-windows-signing.yml')

    def test_bundle_hashes_context_and_exact_file_set(self):
        bundle = self.root / "inputs"
        manifest = self.bundle(bundle)
        signing.verify_bundle(bundle, self.context)
        (bundle / signing.FILES[0]).write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            signing.verify_bundle(bundle, self.context)
        self.bundle(bundle)
        wrong = dict(self.context, run_attempt=2)
        with self.assertRaisesRegex(ValueError, "provenance"):
            signing.verify_bundle(bundle, wrong)
        manifest["files"]["extra.exe"] = "c" * 64
        signing.write_json(bundle / "signing-inputs.json", manifest)
        with self.assertRaisesRegex(ValueError, "file set"):
            signing.verify_bundle(bundle, self.context)

    def test_stage_uses_release_outputs_and_copies_only_allowlisted_inputs(self):
        x64, x86 = self.root / "x64", self.root / "x86"
        for base in (x64, x86):
            base.mkdir()
            (base / "CMakeCache.txt").write_text("CMAKE_CONFIGURATION_TYPES:STRING=Debug;Release\n")
        for name in signing.FILES:
            architecture, relative = name.split("/", 1)
            base = x64 if architecture == "x64" else x86
            path = base / "Release" / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(name.encode())
        (x64 / "KeyKeyTsf.dll").write_bytes(b"stale wrong-config file")
        env = dict(GITHUB_REPOSITORY=signing.REPOSITORY, GITHUB_RUN_ID="123", GITHUB_RUN_ATTEMPT="1",
                   RELEASE_TAG_SHA=self.context["source_sha"])
        destination = self.root / "staged"
        with patch.dict(os.environ, env), patch.object(signing, "run", return_value=self.context["source_sha"]), \
                patch.object(signing, "product_version", return_value="1.3.3"):
            signing.stage(destination, x64, x86, "v1.3.3")
        signing.verify_bundle(destination, self.context)
        self.assertEqual((destination / "x64/KeyKeyTsf.dll").read_bytes(), b"x64/KeyKeyTsf.dll")

    def test_download_success_and_cache_tampering(self):
        source = self.root / "source"
        self.bundle(source)
        archive = self.root / "source.zip"
        self.archive(source, archive)
        self.context["artifact_digest"] = "sha256:" + signing.sha256(archive)
        def fake_download(args, **kwargs):
            kwargs["stdout"].write(archive.read_bytes())
            return subprocess.CompletedProcess(args, 0)
        destination = self.root / "release"
        with patch.object(signing, "provenance", return_value=self.context), \
                patch.object(signing.subprocess, "run", side_effect=fake_download), patch("sys.stdout", new=io.StringIO()):
            signing.download(123, "v1.3.3", destination)
            signing.download(123, "v1.3.3", destination)
            (destination / "inputs" / signing.FILES[0]).write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                signing.download(123, "v1.3.3", destination)

    def test_extract_rejects_traversal_missing_and_duplicate_entries(self):
        source = self.root / "source"
        self.bundle(source)
        archive = self.root / "inputs.zip"
        self.archive(source, archive)
        signing.extract(archive, self.root / "good")
        signing.verify_bundle(self.root / "good", self.context)
        for name in ("../escape.exe", "x64/KeyKeyTsf.dll", "C:/escape.exe"):
            self.archive(source, archive)
            with zipfile.ZipFile(archive, "a") as output:
                with self.assertWarns(UserWarning) if name == "x64/KeyKeyTsf.dll" else nullcontext():
                    output.writestr(name, b"bad")
            with self.assertRaisesRegex(ValueError, "archive entries"):
                signing.extract(archive, self.root / "bad")

    def test_download_fails_before_extract_on_archive_digest_mismatch(self):
        def fake_download(args, **kwargs):
            kwargs["stdout"].write(b"corrupt")
            return subprocess.CompletedProcess(args, 0)
        with patch.object(signing, "provenance", return_value=self.context), \
                patch.object(signing.subprocess, "run", side_effect=fake_download), patch.object(signing, "extract") as extract:
            with self.assertRaisesRegex(ValueError, "digest mismatch"):
                signing.download(123, "v1.3.3", self.root / "release")
            extract.assert_not_called()

    def test_provenance_rejects_failed_fork_wrong_workflow_source_and_artifact(self):
        record = dict(status="completed", conclusion="success", event="release", head_sha="a" * 40,
                      repository=dict(full_name=signing.REPOSITORY), head_repository=dict(full_name=signing.REPOSITORY),
                      workflow_id=1, run_attempt=1)
        artifact = dict(name=signing.artifact_name("1.3.3", 123, 1), id=9, expired=False,
                        workflow_run=dict(head_sha="a" * 40), digest=self.context["artifact_digest"])
        responses = {"actions/runs/123": record, "actions/workflows/1": dict(path=signing.WORKFLOW),
                     "actions/runs/123/artifacts?per_page=100": dict(total_count=1, artifacts=[artifact])}
        with patch.object(signing, "api", side_effect=lambda endpoint: responses[endpoint]), \
                patch.object(signing, "remote_tag", return_value="a" * 40), \
                patch.object(signing, "product_version", return_value="1.3.3"), patch.object(signing, "local_source"):
            self.assertEqual(signing.provenance(123, "v1.3.3"), self.context)
            changes = ((record, "conclusion", "failure"), (record, "event", "pull_request"),
                       (record, "head_repository", dict(full_name="fork/KeyKey")),
                       (responses["actions/workflows/1"], "path", "other.yml"),
                       (responses["actions/workflows/1"], "path", ".github/workflows/package-windows.yml"),
                       (record, "head_sha", "c" * 40), (artifact, "digest", None),
                       (artifact, "workflow_run", dict(head_sha="c" * 40)))
            for obj, key, value in changes:
                previous = obj[key]
                obj[key] = value
                with self.subTest(key=key), self.assertRaises(ValueError):
                    signing.provenance(123, "v1.3.3")
                obj[key] = previous

    def test_signed_receipt_and_checksum_cannot_describe_other_bytes(self):
        package = self.signed(self.root)
        signing.verify_signed(self.root, self.context)
        package.write_bytes(b"modified after signature")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            signing.verify_signed(self.root, self.context)

    def prepare_publish(self):
        destination = self.root / "release"
        self.bundle(destination / "inputs")
        self.archive(destination / "inputs", destination / "inputs.zip")
        self.context["artifact_digest"] = "sha256:" + signing.sha256(destination / "inputs.zip")
        signing.write_json(destination / "context.json", self.context)
        installer = self.signed(destination / "signed")
        return destination, signing.sha256(installer)

    def test_publish_requires_native_verification_and_exact_approved_hash(self):
        destination, digest = self.prepare_publish()
        with patch.object(signing, "provenance", return_value=self.context), patch.object(signing, "native_verify") as native, \
                patch.object(signing, "release_assets") as assets, patch.object(signing, "run") as run:
            with self.assertRaisesRegex(ValueError, "approved SHA"):
                signing.publish(123, "v1.3.3", destination, "0" * 64)
            assets.assert_not_called()
            native.side_effect = ValueError("untrusted signature")
            with self.assertRaisesRegex(ValueError, "untrusted"):
                signing.publish(123, "v1.3.3", destination, digest)
            run.assert_not_called()

    def test_publication_collision_preflight_does_not_upload_or_dispatch(self):
        destination, digest = self.prepare_publish()
        def download(tag, name, directory):
            (Path(directory) / name).write_bytes(b"existing other release bytes")
        with patch.object(signing, "provenance", return_value=self.context), patch.object(signing, "native_verify"), \
                patch.object(signing, "release_assets", return_value={signing.asset_names("1.3.3")[0]: {}}), \
                patch.object(signing, "download_asset", side_effect=download), patch.object(signing, "run") as run:
            with self.assertRaisesRegex(ValueError, "refusing overwrite"):
                signing.publish(123, "v1.3.3", destination, digest)
            run.assert_not_called()

    def test_publish_uploads_without_clobber_reads_back_and_dispatches_mirror(self):
        destination, digest = self.prepare_publish()
        def download(tag, name, directory):
            (Path(directory) / name).write_bytes((destination / "signed" / name).read_bytes())
        with patch.object(signing, "provenance", return_value=self.context), patch.object(signing, "native_verify"), \
                patch.object(signing, "release_assets", return_value={}), \
                patch.object(signing, "download_asset", side_effect=download), patch.object(signing, "run") as run, \
                patch("sys.stdout", new=io.StringIO()):
            signing.publish(123, "v1.3.3", destination, digest)
        calls = [c.args for c in run.call_args_list]
        self.assertEqual(sum(c[:3] == ("gh", "release", "upload") for c in calls), 3)
        self.assertTrue(all("--clobber" not in c for c in calls))
        self.assertEqual(calls[-1][:4], ("gh", "workflow", "run", "mirror-windows-signed.yml"))

    def test_mirror_conditionally_adds_and_reads_back_no_overwrite(self):
        self.signed(self.root)
        receipt = self.root / signing.asset_names("1.3.3")[2]
        env = dict(RELEASE_MIRROR_BUCKET="example-bucket", RELEASE_MIRROR_DISTRIBUTION_ID="EXAMPLE",
                   RELEASE_MIRROR_BASE_URL="https://cdn.example.invalid")
        def aws(*args):
            if args[:3] == ("aws", "s3api", "get-object"):
                Path(args[-1]).write_bytes((self.root / Path(args[-1]).name).read_bytes())
            return json.dumps(dict(Invalidation=dict(Id="EXAMPLE")))
        with patch.dict(os.environ, env), patch.object(signing, "provenance", return_value=self.context), \
                patch.object(signing, "product_version", return_value="1.3.3"), \
                patch.object(signing, "run", side_effect=aws) as run, \
                patch.object(signing, "verify_url") as cdn, \
                patch.object(signing.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as put, \
                patch("sys.stdout", new=io.StringIO()):
            signing.mirror("v1.3.3", self.root, signing.sha256(receipt))
        self.assertEqual(put.call_count, 3)
        for call in put.call_args_list:
            args = call.args[0]
            self.assertEqual(args[args.index("--if-none-match") + 1], "*")
        self.assertEqual(run.call_args_list[-1].args[:3], ("aws", "cloudfront", "wait"))
        self.assertEqual(cdn.call_count, 3)


if __name__ == "__main__":
    unittest.main()
