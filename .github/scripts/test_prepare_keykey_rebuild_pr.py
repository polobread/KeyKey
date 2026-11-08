import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('rebuild_pr', Path(__file__).with_name('prepare-keykey-rebuild-pr.py'))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)

REVISION = 'a' * 40
FINGERPRINT = 'b' * 64
BRANCH = publisher.BRANCH_PREFIX + FINGERPRINT
URL = 'https://github.com/polobread/KeyKey/pull/123'


class RebuildPublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name) / 'output'
        self.root = Path(self.temporary.name) / 'repo'
        self.directory.mkdir()
        self.root.mkdir()
        self.files = ['DataSource/AISyntheticBigram/rebuild-review/latest.json']
        target = self.root / self.files[0]
        target.parent.mkdir(parents=True)
        target.write_text('{"candidate":"changed"}\n')
        self.report = dict(publication_needed=True, publication_fingerprint=FINGERPRINT,
                           publication_reason='Changed source, model or regression content.',
                           decision='adopted', reason='within threshold', validation_articles=131,
                           regression=dict(before=1000, after=1000, delta=0), files=self.files)
        self.event = self.directory / 'event.json'
        self.event.write_text(json.dumps(dict(action='closed', pull_request=dict(
            merged=True, base=dict(ref='master', repo=dict(full_name=publisher.REPOSITORY))))))
        self.environment = dict(GITHUB_REPOSITORY=publisher.REPOSITORY,
                                GITHUB_EVENT_NAME='pull_request_target', GITHUB_REF='refs/heads/master',
                                GITHUB_EVENT_PATH=str(self.event))
        self.existing = []
        self.calls = []
        self.master = REVISION
        self.changed = self.files[0] + '\0'
        self.staged = ''
        self.branch_exists = False
        self.save()

    def save(self):
        (self.directory / 'build-report.json').write_text(json.dumps(self.report))
        (self.directory / 'generated-files.json').write_text(json.dumps(self.files))

    def record(self, state='OPEN', **changes):
        return dict(number=123, url=URL, state=state, headRefName=BRANCH, baseRefName='master',
                    isCrossRepository=False, headRepositoryOwner=dict(login='polobread'), **changes)

    def output(self, root, *args):
        self.assertEqual(root, self.root)
        self.calls.append(args)
        if args == ('git', 'symbolic-ref', '--short', 'HEAD'):
            return 'master'
        if args == ('git', 'rev-parse', 'HEAD'):
            return REVISION
        if args == ('git', 'rev-parse', 'origin/master'):
            return self.master
        if args == ('git', 'diff', '--cached', '--name-only', '-z'):
            return self.staged
        if args == ('git', 'diff', '--name-only', '-z', 'HEAD'):
            return self.changed
        if args == ('git', 'ls-files', '--others', '--exclude-standard', '-z'):
            return ''
        if args[:3] == ('gh', 'pr', 'list'):
            self.assertIn('all', args)
            self.assertEqual(args[args.index('--head') + 1], BRANCH)
            return json.dumps(self.existing)
        if args == ('git', 'ls-remote', '--heads', 'origin', 'refs/heads/master'):
            return self.master + '\trefs/heads/master'
        if args == ('git', 'ls-remote', '--heads', 'origin', 'refs/heads/' + BRANCH):
            return (REVISION + '\trefs/heads/' + BRANCH) if self.branch_exists else ''
        if args[:3] == ('gh', 'pr', 'create'):
            self.assertEqual(args[args.index('--base') + 1], 'master')
            self.assertEqual(args[args.index('--head') + 1], BRANCH)
            body = Path(args[args.index('--body-file') + 1]).read_text()
            self.assertIn(FINGERPRINT, body)
            self.assertIn('Manual review and merge are required', body)
            return URL
        self.fail(f'Unexpected command: {args}')

    def run_command(self, root, *args):
        self.assertEqual(root, self.root)
        self.calls.append(args)
        if args[:3] == ('git', '--literal-pathspecs', 'add'):
            self.assertEqual(args[3:], ('--', *self.files))
            self.staged = self.files[0] + '\0'

    def publish(self):
        with patch.object(publisher, 'output', side_effect=self.output), \
                patch.object(publisher, 'run', side_effect=self.run_command):
            return publisher.publish(self.directory, self.root, self.environment)

    def assert_no_publication_mutations(self):
        self.assertFalse(any(command[:2] in (('git', 'switch'), ('git', 'push')) or
                             command[:3] in (('git', '--literal-pathspecs', 'add'), ('gh', 'pr', 'create')) or
                             'commit' in command for command in self.calls), self.calls)

    def test_noop_never_runs_git_or_github_or_writes_a_pr_body(self):
        self.report['publication_needed'] = False
        self.files = self.report['files'] = []
        self.save()
        self.assertEqual(self.publish(), dict(status='unchanged'))
        self.assertEqual(self.calls, [])
        self.assertFalse((self.directory / 'pull-request.md').exists())

    def test_noop_with_files_is_rejected_without_side_effects(self):
        self.report['publication_needed'] = False
        self.save()
        with self.assertRaisesRegex(ValueError, 'no-op'):
            self.publish()
        self.assertEqual(self.calls, [])

    def test_open_closed_and_merged_reviews_are_reused_without_new_commits_or_pushes(self):
        for state in ('OPEN', 'CLOSED', 'MERGED'):
            with self.subTest(state=state):
                self.calls = []
                self.existing = [self.record(state)]
                self.assertEqual(self.publish(), dict(status='existing', url=URL, state=state))
                self.assert_no_publication_mutations()
                self.assertFalse((self.directory / 'pull-request.md').exists())

    def test_substantive_zero_delta_creates_one_review_on_fingerprint_branch(self):
        self.assertEqual(self.publish(), dict(status='created', url=URL))
        self.assertIn(('git', 'switch', '-c', BRANCH), self.calls)
        self.assertIn(('git', 'push', 'origin', 'HEAD:refs/heads/' + BRANCH), self.calls)
        self.assertFalse(any('--force' in argument for command in self.calls for argument in command))
        self.assertEqual(sum(command[:3] == ('gh', 'pr', 'create') for command in self.calls), 1)

    def test_closed_or_unmerged_event_cannot_publish(self):
        for merged in (False, None):
            self.event.write_text(json.dumps(dict(action='closed', pull_request=dict(
                merged=merged, base=dict(ref='master', repo=dict(full_name=publisher.REPOSITORY))))))
            with self.subTest(merged=merged), self.assertRaisesRegex(ValueError, 'merged pull request'):
                self.publish()
        self.assertEqual(self.calls, [])

    def test_untrusted_event_or_repository_cannot_publish(self):
        for key, value in [('GITHUB_EVENT_NAME', 'pull_request'), ('GITHUB_REF', 'refs/heads/topic'),
                           ('GITHUB_REPOSITORY', 'someone/KeyKey')]:
            original = self.environment[key]
            self.environment[key] = value
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'official master'):
                self.publish()
            self.environment[key] = original
        self.assertEqual(self.calls, [])

    def test_master_advancing_during_rebuild_stops_before_publication(self):
        self.master = 'c' * 40
        with self.assertRaisesRegex(ValueError, 'master changed during the rebuild'):
            self.publish()
        self.assert_no_publication_mutations()
        self.assertFalse(any(command[0] == 'gh' for command in self.calls))

    def test_unexpected_worktree_or_index_changes_cannot_be_staged(self):
        self.changed += 'source.py\0'
        with self.assertRaisesRegex(ValueError, 'outside generated-files'):
            self.publish()
        self.assert_no_publication_mutations()
        self.changed = self.files[0] + '\0'
        self.staged = 'source.py\0'
        with self.assertRaisesRegex(ValueError, 'index must be empty'):
            self.publish()
        self.assert_no_publication_mutations()

    def test_invalid_duplicate_missing_and_symlink_paths_are_rejected(self):
        valid = self.files[0]
        outside = Path(self.temporary.name) / 'outside.json'
        outside.write_text('{}')
        (self.root / 'link.json').symlink_to(outside)
        for path in ('../outside.json', str(outside), 'a/../b', 'a//b', '-option', ':(glob)**',
                     '.git/config', 'new\nfile', 'link.json', 'missing.json'):
            self.files = self.report['files'] = [path]
            self.save()
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, 'generated path|Generated path'):
                self.publish()
        self.files = self.report['files'] = [valid, valid]
        self.save()
        with self.assertRaisesRegex(ValueError, 'duplicates'):
            self.publish()
        self.assertEqual(self.calls, [])

    def test_branch_without_review_is_not_overwritten_or_reopened(self):
        self.branch_exists = True
        with self.assertRaisesRegex(ValueError, 'already exists without a matching PR'):
            self.publish()
        self.assert_no_publication_mutations()

    def test_cross_repository_pull_request_does_not_suppress_official_review(self):
        fork = self.record()
        fork.update(isCrossRepository=True, headRepositoryOwner=dict(login='someone'))
        self.existing = [fork]
        self.assertEqual(self.publish()['status'], 'created')

    def test_github_read_failure_stops_before_mutation(self):
        def failing_output(root, *args):
            if args[:3] == ('gh', 'pr', 'list'):
                raise subprocess.CalledProcessError(1, args)
            return self.output(root, *args)
        with patch.object(publisher, 'output', side_effect=failing_output), \
                patch.object(publisher, 'run', side_effect=self.run_command), self.assertRaises(subprocess.CalledProcessError):
            publisher.publish(self.directory, self.root, self.environment)
        self.assert_no_publication_mutations()

    def test_real_git_push_keeps_master_and_unrelated_files_unchanged(self):
        remote = Path(self.temporary.name) / 'remote.git'
        def git(*args, cwd=self.root):
            return subprocess.check_output(['git', *args], cwd=cwd, text=True,
                                           stderr=subprocess.PIPE).strip()
        git('init', '--bare', str(remote))
        git('init', '-b', 'master')
        git('config', 'user.name', 'Rebuild test')
        git('config', 'user.email', 'rebuild-test@example.invalid')
        (self.root / self.files[0]).write_text('{"candidate":"previous"}\n')
        (self.root / 'keep.txt').write_text('keep this source unchanged\n')
        git('add', '--', *self.files, 'keep.txt')
        git('commit', '-m', 'baseline')
        git('remote', 'add', 'origin', str(remote))
        git('push', '-u', 'origin', 'master')
        base = git('rev-parse', 'HEAD')
        (self.root / self.files[0]).write_text('{"candidate":"changed"}\n')
        original_output = publisher.output
        def local_output(root, *args):
            if args[:3] == ('gh', 'pr', 'list'):
                return '[]'
            if args[:3] == ('gh', 'pr', 'create'):
                self.assertEqual(git('branch', '--show-current'), BRANCH)
                return URL
            return original_output(root, *args)
        def local_run(root, *args):
            if args == ('gh', 'auth', 'setup-git'):
                return
            subprocess.run(args, cwd=root, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        with patch.object(publisher, 'output', side_effect=local_output), \
                patch.object(publisher, 'run', side_effect=local_run):
            self.assertEqual(publisher.publish(self.directory, self.root, self.environment)['status'], 'created')
        self.assertEqual(git('rev-parse', 'master'), base)
        self.assertEqual(git('rev-parse', 'refs/heads/master', cwd=remote), base)
        head = git('rev-parse', 'refs/heads/' + BRANCH, cwd=remote)
        self.assertNotEqual(head, base)
        self.assertEqual(git('diff', '--name-only', base, head), self.files[0])
        self.assertEqual(git('show', head + ':keep.txt'), 'keep this source unchanged')
        self.assertEqual(git('show', head + ':' + self.files[0]), '{"candidate":"changed"}')

    def test_failed_or_incomplete_publication_report_cannot_publish(self):
        for name, value in [('publication_fingerprint', 'bad'), ('decision', 'unknown')]:
            report = copy.deepcopy(self.report)
            self.report[name] = value
            self.save()
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.publish()
            self.report = report
        self.assertEqual(self.calls, [])


if __name__ == '__main__':
    unittest.main()
