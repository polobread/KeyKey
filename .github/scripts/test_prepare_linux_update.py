import base64
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('linux_update', Path(__file__).with_name('prepare-linux-update.py'))
update = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update)
SOURCE = 'a' * 40
MASTER = 'b' * 40
VERSION = '1.3.8'
TAG = 'v' + VERSION
RUN = 123


def deb_bytes(package, version, architecture, control_extra=''):
    control = f'Package: {package}\nVersion: {version}\nArchitecture: {architecture}\n' + control_extra
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w:xz') as bundle:
        member = tarfile.TarInfo('./control')
        member.size = len(control.encode())
        bundle.addfile(member, io.BytesIO(control.encode()))
    data = buffer.getvalue()
    header = f'{"control.tar.xz/":<16}{0:<12}{0:<6}{0:<6}{100644:<8}{len(data):<10}`\n'.encode()
    return b'!<arch>\n' + header + data + (b'\n' if len(data) % 2 else b'')


def empty_feed():
    return (f'<rss version="2.0" xmlns:keykey="{update.updates.UNIX}"><channel>'
            '<title>Unix</title><description>Test</description><keykey:schemaVersion>1</keykey:schemaVersion>'
            '</channel></rss>').encode()


class LinuxUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.directory = self.root / 'candidate'
        self.originals = self.directory / 'original'
        self.originals.mkdir(parents=True)
        self.feed = self.root / 'update/stable/unix-fcitx5.xml'
        self.feed.parent.mkdir(parents=True)
        self.feed.write_bytes(empty_feed())
        for package, version, arch in [('fcitx5-chichi77-keykey', VERSION + '-1+ubuntu24.04', 'amd64'),
                ('chichi77-keykey-data', VERSION + '-1+ubuntu24.04', 'all'),
                ('gnome-shell-extension-keykey-kimpanel', '83+keykey1-1+ubuntu24.04', 'all')]:
            path = self.originals / f'{package}_{version}_{arch}.deb'
            path.write_bytes(deb_bytes(package, version, arch))
        panel = self.originals / 'gnome-shell-extension-keykey-kimpanel_83+keykey1-1+ubuntu24.04_source.tar.gz'
        panel.write_bytes(b'isolated source fixture')
        self.info = dict(platform='linux', version=VERSION, release_tag=TAG, release_version=VERSION,
            update_channel='stable', source_sha=SOURCE, tag_sha=SOURCE,
            run_url=f'https://github.com/polobread/KeyKey/actions/runs/{RUN}', run_attempt='1')
        self.run = dict(id=RUN, repository=dict(full_name=update.REPOSITORY),
            head_repository=dict(full_name=update.REPOSITORY), path='.github/workflows/linux-ci.yml',
            event='release', status='completed', conclusion='success', head_sha=SOURCE, run_attempt=1)
        self.jobs = dict(total_count=3, jobs=[dict(name=name, conclusion='success', steps=[])
            for name in ['Full Ubuntu 24.04 build, packages, and GTK3/GTK4/Qt6 X11 E2E',
                         'Full Ubuntu 22.04 minimum API build and package lifecycle',
                         'Publish Ubuntu 24.04 packages to the GitHub Release']])
        self.jobs['jobs'][0]['steps'] = [dict(name='Test package install, upgrade, removal, reinstall, and X11 typing',
                                              conclusion='success')]
        self.refresh_records()

    def refresh_records(self):
        packages = sorted(self.originals.glob('*.deb')) + sorted(self.originals.glob('*_source.tar.gz'))
        checksum = self.originals / 'SHA256SUMS'
        checksum.write_text(''.join(f'{update.assets.digest(path)}  ./{path.name}\n' for path in packages))
        paths = update.assets.verified_assets(self.originals, 'linux', VERSION)
        self.info['assets'] = [dict(name=path.name, size=path.stat().st_size, sha256=update.assets.digest(path)) for path in paths]
        self.info_file = self.originals / f'chichi77-KeyKey-{VERSION}-linux-build-info.json'
        self.info_file.write_text(json.dumps(self.info))
        self.published = dict(tag_name=TAG, draft=False, prerelease=False,
            assets=[dict(name=path.name, size=path.stat().st_size, digest='sha256:' + update.assets.digest(path))
                    for path in [*paths, self.info_file]])

    def api(self, endpoint):
        if endpoint == f'releases/tags/{TAG}': return self.published
        if endpoint == f'git/ref/tags/{TAG}': return dict(object=dict(type='commit', sha=SOURCE))
        if endpoint == f'compare/{SOURCE}...{MASTER}': return dict(status='ahead', merge_base_commit=dict(sha=SOURCE))
        if endpoint.startswith('contents/'):
            return dict(content=base64.b64encode(f'project(KeyKeyLinux VERSION {VERSION} LANGUAGES CXX)'.encode()).decode())
        if endpoint == f'actions/runs/{RUN}': return self.run
        if endpoint == f'actions/runs/{RUN}/attempts/1/jobs?per_page=100': return self.jobs
        raise AssertionError(endpoint)

    def prepare(self):
        with patch.object(update, 'ROOT', self.root), patch.object(update, 'api', side_effect=self.api), \
                patch.object(update, 'output', return_value=MASTER), patch.object(update.assets, 'verify_cdn_bytes'):
            return update.prepare(TAG, self.directory, str(RUN))

    def test_only_stable_tags(self):
        self.assertEqual(update.version_for_tag(TAG), VERSION)
        for tag in [None, VERSION, 'master', 'v1.3.8-beta1', 'v01.3.8', 'v1.3.8/../../master']:
            with self.subTest(tag=tag), self.assertRaises(ValueError): update.version_for_tag(tag)

    def test_annotated_tag_resolution(self):
        with patch.object(update, 'api', side_effect=[dict(object=dict(type='tag', sha='c'*40)),
                                                     dict(object=dict(type='commit', sha=SOURCE))]):
            self.assertEqual(update.tag_commit(TAG), SOURCE)
        with patch.object(update, 'api', return_value=dict(object=dict(type='tree', sha=SOURCE))), self.assertRaises(ValueError):
            update.tag_commit(TAG)

    def test_source_requires_merged_linux_version(self):
        with patch.object(update, 'api', side_effect=self.api): update.verify_source(TAG, SOURCE, MASTER)
        for first, second in [(dict(status='diverged', merge_base_commit=dict(sha=SOURCE)), {}),
                (dict(status='ahead', merge_base_commit=dict(sha=SOURCE)),
                 dict(content=base64.b64encode(b'project(KeyKeyLinux VERSION 1.3.7 LANGUAGES CXX)').decode()))]:
            with patch.object(update, 'api', side_effect=[first,second]), self.assertRaises(ValueError):
                update.verify_source(TAG, SOURCE, MASTER)

    def test_run_requires_official_success_exact_source_attempt_and_trigger(self):
        with patch.object(update, 'api', side_effect=self.api): update.verify_run(self.info, SOURCE, str(RUN))
        for field, value in [('conclusion','cancelled'),('conclusion','failure'),('event','pull_request'),
                ('status','in_progress'),('path','.github/workflows/other.yml'),('head_sha','c'*40),
                ('run_attempt',2),('head_repository',dict(full_name='someone/fork'))]:
            with self.subTest(field=field,value=value), patch.object(update,'api',return_value=dict(self.run,**{field:value})), \
                    self.assertRaises(ValueError): update.verify_run(self.info,SOURCE)
        with patch.object(update,'api',side_effect=self.api), self.assertRaisesRegex(ValueError,'another workflow'):
            update.verify_run(self.info,SOURCE,'456')

    def test_publication_minimum_api_and_lifecycle_gates_must_pass(self):
        for index in range(3):
            jobs = copy.deepcopy(self.jobs)
            jobs['jobs'][index]['conclusion']='skipped'
            with patch.object(update,'api',side_effect=[self.run,jobs]), self.assertRaises(ValueError):
                update.verify_run(self.info,SOURCE)
        jobs=copy.deepcopy(self.jobs); jobs['jobs'][0]['steps'][0]['conclusion']='failure'
        with patch.object(update,'api',side_effect=[self.run,jobs]), self.assertRaisesRegex(ValueError,'lifecycle'):
            update.verify_run(self.info,SOURCE)
        jobs=copy.deepcopy(self.jobs); jobs['jobs'].append(jobs['jobs'][0]); jobs['total_count']=4
        with patch.object(update,'api',side_effect=[self.run,jobs]), self.assertRaises(ValueError):
            update.verify_run(self.info,SOURCE)

    def test_cached_download_verifies_digest_and_never_overwrites(self):
        with patch.object(update.assets,'recovery_download') as download:
            self.assertEqual(update.download(TAG,self.info_file.name,self.originals,self.published),self.info_file)
            self.info_file.write_bytes(b'tampered')
            with self.assertRaisesRegex(ValueError,'bytes differ'):
                update.download(TAG,self.info_file.name,self.originals,self.published)
            download.assert_not_called()

    def test_symlink_download_is_rejected_before_network_or_writes(self):
        self.info_file.unlink()
        self.info_file.symlink_to(self.root / 'missing-outside')
        with patch.object(update.assets,'recovery_download') as download,self.assertRaisesRegex(ValueError,'symlink'):
            update.download(TAG,self.info_file.name,self.originals,self.published)
        download.assert_not_called()

    def test_same_version_architecture_changes_need_manual_review(self):
        original=update.updated_feed(empty_feed(),VERSION)
        changed=original.replace(b'>amd64<',b'>arm64<')
        with self.assertRaisesRegex(ValueError,'same-version'):
            update.updated_feed(changed,VERSION)

    def test_asset_digest_missing_or_duplicate_rejected(self):
        for records in [[],[self.published['assets'][-1]]*2,
                        [dict(self.published['assets'][-1],digest=None)]]:
            with patch.object(update.assets,'recovery_download') as download, self.assertRaises(ValueError):
                update.download(TAG,self.info_file.name,self.originals,dict(assets=records))
            download.assert_not_called()

    def test_debian_control_rejects_malformed_and_duplicate_fields(self):
        path=self.originals/'control-fixture.deb'
        for raw in [b'not ar',b'!<arch>\ntruncated',deb_bytes('fixture','1','amd64','Version: 2\n')]:
            path.write_bytes(raw)
            with self.subTest(raw=raw[:20]),self.assertRaises(ValueError): update.deb_control(path)

    def test_packages_verify_github_cdn_checksums_control_and_build_info(self):
        with patch.object(update.assets,'verify_cdn_bytes') as cdn:
            self.assertEqual(update.verify_packages(self.originals,self.published,self.info,TAG,SOURCE),self.info['assets'])
            self.assertEqual(cdn.call_count,5)
        for field,value in [('version','1.3.7'),('source_sha','b'*40),('tag_sha','b'*40),('platform','macos')]:
            with patch.object(update.assets,'verify_cdn_bytes'),self.assertRaises(ValueError):
                update.verify_packages(self.originals,self.published,dict(self.info,**{field:value}),TAG,SOURCE)
        (self.originals/'SHA256SUMS').write_text('0'*64+'  bad.deb\n')
        with self.assertRaises(ValueError): update.verify_packages(self.originals,self.published,self.info,TAG,SOURCE)

    def test_debian_wrong_architecture_or_version_rejected_even_with_consistent_hashes(self):
        path=next(self.originals.glob('fcitx5*.deb'))
        for version,arch in [(VERSION+'-1+ubuntu24.04','arm64'),('1.3.7-1+ubuntu24.04','amd64')]:
            path.write_bytes(deb_bytes('fcitx5-chichi77-keykey',version,arch));self.refresh_records()
            with patch.object(update.assets,'verify_cdn_bytes'),self.assertRaisesRegex(ValueError,'identity/version/architecture'):
                update.verify_packages(self.originals,self.published,self.info,TAG,SOURCE)

    def test_cdn_mismatch_stops_preparation(self):
        with patch.object(update.assets,'verify_cdn_bytes',side_effect=ValueError('CDN Linux bytes differ')),self.assertRaises(ValueError):
            update.verify_packages(self.originals,self.published,self.info,TAG,SOURCE)

    def test_feed_preserves_history_is_notification_only_and_repeat_is_noop(self):
        old=update.updated_feed(empty_feed(),'1.3.7')
        new=update.updated_feed(old,VERSION)
        entries=update.updates.parse_feed(new,'stable')
        self.assertEqual([entry['version'] for entry in entries],[VERSION,'1.3.7'])
        self.assertIsNone(update.updated_feed(new,VERSION))
        self.assertNotIn(b'<enclosure',new)
        self.assertIn('ports／pkg'.encode(),new)
        with self.assertRaisesRegex(ValueError,'downgrade'): update.updated_feed(new,'1.3.6')
        with self.assertRaises(ValueError): update.updated_feed(new,'1.3.9-beta1')

    def test_candidate_client_linux_arch_filter_and_freebsd_shared_notice(self):
        xml=update.updated_feed(empty_feed(),VERSION)
        get=lambda _:xml
        for system,machine,expected in [('Linux','amd64',VERSION),('Linux','aarch64',None),('FreeBSD','aarch64',VERSION)]:
            value=update.updates.latest_release('1.3.7',system,machine,get=get)
            self.assertEqual(value['version'] if value else None,expected)
        self.assertIsNone(update.updates.latest_release(VERSION,'Linux','amd64',get=get))

    def test_prepare_is_readonly_except_candidate_and_evidence(self):
        old=self.feed.read_bytes()
        self.assertTrue(self.prepare())
        self.assertEqual(self.feed.read_bytes(),old)
        plan=json.loads((self.directory/'plan.json').read_text())
        self.assertEqual(plan['assets'],self.info['assets'])
        self.assertEqual(plan['base_sha'],MASTER)
        self.assertEqual(plan['source_sha'],SOURCE)
        self.assertEqual(plan['feed_sha256'],update.assets.digest(self.directory/'proposal/unix-fcitx5.xml'))
        self.feed.write_bytes(update.updated_feed(old,VERSION))
        self.assertFalse(self.prepare())

    def test_draft_prerelease_and_unsafe_asset_names_cannot_prepare(self):
        for field in ('draft','prerelease'):
            bad=dict(self.published,**{field:True})
            with patch.object(update,'api',return_value=bad),self.assertRaises(ValueError):
                update.prepare(TAG,self.directory)
        self.info['assets'][0]['name']='../outside';self.info_file.write_text(json.dumps(self.info))
        entry=self.published['assets'][-1];entry.update(size=self.info_file.stat().st_size,digest='sha256:'+update.assets.digest(self.info_file))
        with patch.object(update,'ROOT',self.root),patch.object(update,'api',side_effect=self.api), \
                patch.object(update,'output',return_value=MASTER),patch.object(update.assets,'verify_cdn_bytes'),self.assertRaisesRegex(ValueError,'Unsafe'):
            update.prepare(TAG,self.directory)

    def test_revalidation_detects_changed_github_bytes(self):
        self.prepare();plan=json.loads((self.directory/'plan.json').read_text())
        with patch.object(update,'api',side_effect=self.api),patch.object(update.assets,'verify_cdn_bytes'):
            update.revalidate(self.directory,plan)
            self.published['assets'][0]['digest']='sha256:'+'0'*64
            with self.assertRaisesRegex(ValueError,'bytes differ'):update.revalidate(self.directory,plan)

    def pr_environment(self):
        return patch.dict(os.environ,dict(GITHUB_REF='refs/heads/master',GITHUB_REPOSITORY=update.REPOSITORY,
                                         GITHUB_EVENT_NAME='workflow_run'))

    def test_unreviewed_refs_cannot_mutate_git(self):
        with patch.dict(os.environ,dict(GITHUB_REF='refs/heads/feature')),patch.object(update.subprocess,'run') as run, \
                self.assertRaisesRegex(ValueError,'reviewed official master'):update.open_pr(self.directory)
        run.assert_not_called()

    def test_stale_master_moved_tag_existing_branch_and_tampering_cannot_push(self):
        self.prepare()
        variants=[('stale',[MASTER,'c'*40],SOURCE),('tag',[], 'c'*40),('existing',[MASTER,MASTER,'existing'],SOURCE)]
        for label,outputs,tag in variants:
            with self.subTest(label=label),self.pr_environment(),patch.object(update,'tag_commit',return_value=tag), \
                    patch.object(update,'output',side_effect=outputs),patch.object(update,'revalidate'), \
                    patch.object(update.subprocess,'run') as run,self.assertRaises(ValueError):update.open_pr(self.directory)
            run.assert_not_called()
        (self.directory/'proposal/unix-fcitx5.xml').write_text('tampered')
        with self.pr_environment(),patch.object(update,'tag_commit',return_value=SOURCE),patch.object(update,'output',side_effect=[MASTER,MASTER]), \
                patch.object(update,'revalidate'),patch.object(update.subprocess,'run') as run,self.assertRaises(ValueError):update.open_pr(self.directory)
        run.assert_not_called()

    def test_open_pr_commits_only_unix_feed_to_work_branch_and_never_merges(self):
        self.prepare()
        with self.pr_environment(),patch.object(update,'ROOT',self.root),patch.object(update,'tag_commit',return_value=SOURCE), \
                patch.object(update,'output',side_effect=[MASTER,MASTER,'']),patch.object(update,'revalidate') as revalidate, \
                patch.object(update.subprocess,'run') as run:update.open_pr(self.directory)
        revalidate.assert_called_once()
        commands=[call.args[0] for call in run.call_args_list]
        self.assertIn(['git','add','--',str(self.feed)],commands)
        self.assertIn(['git','push','origin','HEAD:refs/heads/codex/linux-update-'+TAG],commands)
        self.assertTrue(any(command[:3]==['gh','pr','create'] for command in commands))
        self.assertFalse(any('merge' in command or 'master:master' in command for command in commands))


if __name__ == '__main__':
    unittest.main()
