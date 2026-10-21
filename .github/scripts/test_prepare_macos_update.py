import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('macos_update', Path(__file__).with_name('prepare-macos-update.py'))
update = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update)

OPENSSL = os.environ.get('KEYKEY_TEST_OPENSSL', 'openssl')
SOURCE = 'a' * 40


class MacUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.package = self.root / 'chichi77-KeyKey-1.3.7-macos-arm64.pkg.zip'
        self.package.write_bytes(b'isolated-package-fixture')
        self.checksum = update.metadata.digest(self.package)
        self.package.with_name(self.package.name + '.sha256').write_text(f'{self.checksum}  {self.package.name}\n')
        self.asset = dict(name=self.package.name, size=self.package.stat().st_size, digest='sha256:' + self.checksum)
        self.record = dict(assets=[self.asset])
        self.info = dict(platform='macos', version='1.3.7', release_tag='v1.3.7', source_sha=SOURCE,
                         tag_sha=SOURCE, assets=[dict(name=self.package.name, size=self.asset['size'], sha256=self.checksum)],
                         run_url='https://github.com/polobread/KeyKey/actions/runs/123', run_attempt='1')

    def signing_fixture(self):
        key = self.root / 'private.pem'
        subprocess.run([OPENSSL, 'genpkey', '-algorithm', 'ED25519', '-out', str(key)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        public = update.metadata.public_key(key, OPENSSL)
        name = f'KeyKey-1.3.7-macos-arm64-{self.checksum}.pkg.zip'
        path = self.root / 'signed/packages' / name
        path.parent.mkdir(parents=True)
        path.write_bytes(self.package.read_bytes())
        entry = dict(target='macos-arm64', version='1.3.7', release_tag='v1.3.7',
                     source_sha=SOURCE, tag_sha=SOURCE, minimum_system_version='15.0.0',
                     name=name, sha256=self.checksum,
                     size=path.stat().st_size, ed25519_signature=update.metadata.sign(path, key, OPENSSL),
                     url=f'https://github.com/polobread/KeyKey/releases/download/v1.3.7/{name}')
        (self.root / 'proposal').mkdir()
        document = self.root / 'proposal/metadata.json'
        document.write_text(json.dumps(dict(schema_version=1, channel='stable', releases=[entry])))
        (self.root / 'proposal/metadata.json.sig').write_text(update.metadata.sign(document, key, OPENSSL))
        (self.root / 'proposal/macos-arm64.xml').write_bytes(update.metadata.appcast(entry))
        (self.root / 'plan.json').write_text(json.dumps(dict(version='1.3.7', release_tag='v1.3.7', source_sha=SOURCE, sha256=self.checksum, size=self.asset['size'])))
        return key, public, entry

    def test_only_stable_tags_are_accepted(self):
        self.assertEqual(update.stable_version('v1.3.7'), '1.3.7')
        for tag in ['1.3.7', 'v1.3.7-beta1', 'v01.3.7', 'v1.3.7/../../master', 'master']:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                update.stable_version(tag)

    def test_original_package_must_match_three_independent_records(self):
        self.assertEqual(update.validate_provenance(self.info, self.record, self.package, '1.3.7', SOURCE), self.checksum)
        cases = [('source_sha', 'b' * 40), ('tag_sha', 'b' * 40), ('platform', 'windows'), ('version', '1.3.6')]
        for field, value in cases:
            bad = dict(self.info, **{field: value})
            with self.subTest(field=field), self.assertRaises(ValueError):
                update.validate_provenance(bad, self.record, self.package, '1.3.7', SOURCE)
        bad_record = dict(assets=[dict(self.asset, digest='sha256:' + '0' * 64)])
        with self.assertRaisesRegex(ValueError, 'disagree'):
            update.validate_provenance(self.info, bad_record, self.package, '1.3.7', SOURCE)
        self.package.with_name(self.package.name + '.sha256').write_text('0' * 64 + '  ' + self.package.name)
        with self.assertRaisesRegex(ValueError, 'checksum file'):
            update.validate_provenance(self.info, self.record, self.package, '1.3.7', SOURCE)

    def test_duplicate_and_missing_asset_digests_are_rejected(self):
        for assets in [[], [self.asset, self.asset], [dict(self.asset, digest=None)], [dict(self.asset, size=0)]]:
            with self.subTest(assets=assets), self.assertRaises(ValueError):
                update.asset_record(dict(assets=assets), self.package.name)

    def test_existing_download_is_verified_and_never_clobbered(self):
        with patch.object(update.subprocess, 'run') as run:
            self.assertEqual(update.download('v1.3.7', self.record, self.package.name, self.root), self.package)
            run.assert_not_called()
            self.package.write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'Published bytes differ'):
                update.download('v1.3.7', self.record, self.package.name, self.root)
            run.assert_not_called()

    def test_release_source_must_be_merged_into_reviewed_master(self):
        with patch.object(update, "api", return_value=dict(status="ahead", merge_base_commit=dict(sha=SOURCE))):
            update.validate_merged_source(SOURCE, "b" * 40)
        for status, merge_base in [("diverged", "c" * 40), ("behind", "b" * 40), ("ahead", "c" * 40)]:
            with self.subTest(status=status), patch.object(update, "api", return_value=dict(
                    status=status, merge_base_commit=dict(sha=merge_base))), self.assertRaisesRegex(ValueError, "reviewed master"):
                update.validate_merged_source(SOURCE, "b" * 40)

    def test_only_successful_official_release_runs_can_sign(self):
        run = dict(id=123, repository=dict(full_name=update.REPOSITORY), head_repository=dict(full_name=update.REPOSITORY),
                   path='.github/workflows/package-macos.yml', event='release', conclusion='success',
                   head_sha=SOURCE, run_attempt=1)
        with patch.object(update, 'api', return_value=run):
            update.validate_run(self.info, SOURCE, '123')
            with self.assertRaisesRegex(ValueError, 'another workflow'):
                update.validate_run(self.info, SOURCE, '456')
        cases = [('repository', dict(full_name='attacker/KeyKey')), ('head_repository', dict(full_name='attacker/KeyKey')),
                 ('event', 'pull_request'), ('conclusion', 'failure'), ('head_sha', 'b' * 40),
                 ('path', '.github/workflows/other.yml'), ('run_attempt', 2)]
        for field, value in cases:
            with self.subTest(field=field), patch.object(update, 'api', return_value=dict(run, **{field: value})), \
                    self.assertRaisesRegex(ValueError, 'successful official'):
                update.validate_run(self.info, SOURCE)

    def test_prepare_rejects_downgrades_or_changed_same_version_and_skips_exact_repeat(self):
        root = self.root / "checkout"
        stable = root / "update/stable"
        stable.mkdir(parents=True)
        info_path = self.root / "info.json"
        info_path.write_text(json.dumps(self.info))
        def fake_download(tag, record, name, directory):
            return info_path if name.endswith("build-info.json") else self.package
        for version, checksum, outcome in [("1.3.8", self.checksum, "downgrade"),
                                           ("1.3.7", "0" * 64, "different bytes"),
                                           ("1.3.7", self.checksum, None)]:
            (stable / "metadata.json").write_text(json.dumps(dict(releases=[
                dict(target="macos-arm64", version=version, sha256=checksum)])))
            with self.subTest(version=version, checksum=checksum), \
                    patch.object(update, "ROOT", root), patch.object(update, "release_record", return_value=("1.3.7", self.record)), \
                    patch.object(update, "tag_commit", return_value=SOURCE), patch.object(update, "validate_merged_source"), \
                    patch.object(update, "download", side_effect=fake_download), \
                    patch.object(update, "validate_provenance", return_value=self.checksum), patch.object(update, "validate_run"), \
                    patch.object(update.feeds, "channel_snapshot"):
                directory = self.root / ("prepare-" + version + checksum[:2])
                if outcome:
                    with self.assertRaisesRegex(ValueError, outcome):
                        update.prepare("v1.3.7", directory)
                else:
                    self.assertFalse(update.prepare("v1.3.7", directory))
                self.assertFalse((directory / "plan.json").exists())

    def test_untrusted_package_is_rejected_before_payload_expansion(self):
        with patch.object(update.metadata, 'verify_platform_package', side_effect=ValueError('not notarized')), \
                patch.object(update.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'not notarized'):
                update.package_info(self.package, '1.3.7')
            run.assert_not_called()

    def test_merge_preserves_other_platform_records_and_replaces_only_mac(self):
        windows = dict(target='windows-x64', sha256='b' * 64, ed25519_signature='existing-signature')
        old = dict(target='macos-arm64', version='1.3.6')
        document = dict(schema_version=1, channel='stable', generated_at='old', releases=[windows, old],
                        package_managers=dict(linux='distribution repository'))
        original = copy.deepcopy(document)
        new = dict(target='macos-arm64', version='1.3.7')
        merged = update.merged_document(document, new)
        self.assertEqual(document, original)
        self.assertEqual(merged['releases'], [windows, new])
        self.assertEqual(merged['package_managers'], original['package_managers'])

    def test_private_key_mismatch_stops_before_reading_or_signing_package(self):
        key = self.root / 'private.pem'
        key.write_text('fixture that must never reach openssl')
        with patch.object(update.subprocess, 'run', return_value=SimpleNamespace(returncode=1)), \
                patch.object(update.metadata, 'public_key', return_value='wrong'), \
                patch.object(update, 'pinned_key', return_value='reviewed'), \
                patch.object(update, 'package_info') as native:
            with self.assertRaisesRegex(ValueError, 'does not match'):
                update.sign_candidate(self.root, key, OPENSSL)
            native.assert_not_called()

    def test_tracked_private_key_is_rejected(self):
        key = self.root / 'tracked.pem'
        key.write_text('fixture that must not be read')
        with patch.object(update.subprocess, 'run', return_value=SimpleNamespace(returncode=0)), \
                patch.object(update.metadata, 'public_key') as public:
            with self.assertRaisesRegex(ValueError, 'tracked or staged'):
                update.sign_candidate(self.root, key, OPENSSL)
            public.assert_not_called()

    def test_existing_immutable_asset_is_reused_without_upload(self):
        _, public, entry = self.signing_fixture()
        record = dict(assets=[dict(name=entry['name'], size=entry['size'], digest='sha256:' + self.checksum), self.asset])
        with patch.object(update, 'release_record', return_value=('1.3.7', record)), \
                patch.object(update, 'tag_commit', return_value=SOURCE), patch.object(update, 'pinned_key', return_value=public), \
                patch.object(update.feeds, 'reviewed_key', return_value=public), \
                patch.object(update, 'verify_remote') as readback, patch.object(update.subprocess, 'run', wraps=subprocess.run) as run:
            update.stage_asset(self.root, OPENSSL)
            self.assertFalse(any(call.args[0][:3] == ['gh', 'release', 'upload'] for call in run.call_args_list))
            readback.assert_called_once()
        record['assets'][0]['digest'] = 'sha256:' + '0' * 64
        with patch.object(update, 'release_record', return_value=('1.3.7', record)), \
                patch.object(update, 'tag_commit', return_value=SOURCE), patch.object(update, 'pinned_key', return_value=public), \
                patch.object(update.feeds, 'reviewed_key', return_value=public), \
                patch.object(update, 'verify_remote') as readback:
            with self.assertRaisesRegex(ValueError, 'never overwrite'):
                update.stage_asset(self.root, OPENSSL)
            readback.assert_not_called()

    def test_remote_bytes_and_ed25519_must_both_match(self):
        _, public, entry = self.signing_fixture()
        def response(data):
            stream = io.BytesIO(data)
            stream.geturl = lambda: entry['url']
            return stream
        with patch.object(update, 'pinned_key', return_value=public):
            with patch.object(update, 'urlopen', return_value=response(self.package.read_bytes())):
                update.verify_remote(entry, OPENSSL)
            for data in [b'corrupt', self.package.read_bytes() + b'extra']:
                with patch.object(update, 'urlopen', return_value=response(data)), self.assertRaises(ValueError):
                    update.verify_remote(entry, OPENSSL)
            entry['ed25519_signature'] = 'A' * 86 + '=='
            with patch.object(update, 'urlopen', return_value=response(self.package.read_bytes())), self.assertRaises(ValueError):
                update.verify_remote(entry, OPENSSL)

    def test_unreviewed_refs_and_stale_master_cannot_push_a_pr(self):
        with patch.dict(os.environ, dict(GITHUB_REF='refs/heads/feature', GITHUB_REPOSITORY=update.REPOSITORY,
                                        GITHUB_EVENT_NAME='workflow_dispatch')):
            with self.assertRaisesRegex(ValueError, 'reviewed master'):
                update.open_pr(self.root, OPENSSL)
        (self.root / 'plan.json').write_text(json.dumps(dict(base_sha=SOURCE)))
        with patch.dict(os.environ, dict(GITHUB_REF='refs/heads/master', GITHUB_REPOSITORY=update.REPOSITORY,
                                        GITHUB_EVENT_NAME='workflow_run')), \
                patch.object(update, 'output', return_value='b' * 40 + '\trefs/heads/master'), \
                patch.object(update.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'Master advanced'):
                update.open_pr(self.root, OPENSSL)
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
