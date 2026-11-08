#!/usr/bin/env python3
"""Publish a substantive dictionary rebuild once, for maintainer review only."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = 'polobread/KeyKey'
BRANCH_PREFIX = 'codex/keykey-db-rebuild-'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def output(root, *args):
    return subprocess.check_output(args, cwd=root, text=True).strip()


def run(root, *args):
    subprocess.run(args, cwd=root, check=True)


def generated_paths(root, files):
    require(isinstance(files, list) and all(isinstance(path, str) for path in files),
            'Generated files must be a list of repository-relative paths')
    require(len(files) == len(set(files)), 'Generated files must not contain duplicates')
    for path in files:
        relative = PurePosixPath(path)
        require(path and not relative.is_absolute() and relative.as_posix() == path and
                all(part not in ('', '.', '..', '.git') and not part.startswith(('-', ':')) for part in relative.parts) and
                not any(character in path for character in ('\\', '\0', '\n', '\r', '\t')),
                f'Invalid generated path: {path!r}')
        target = root / path
        require(target.is_file() and not any(parent.is_symlink() for parent in [target, *target.parents]
                                              if parent != root and root in parent.parents) and
                target.resolve().is_relative_to(root.resolve()),
                f'Generated path is not a regular file inside the checkout: {path}')
    return sorted(files)


def validate_context(environment):
    require(environment.get('GITHUB_REPOSITORY') == REPOSITORY and
            environment.get('GITHUB_EVENT_NAME') == 'pull_request_target' and
            environment.get('GITHUB_REF') == 'refs/heads/master',
            'Only a merged pull request on the official master may publish rebuilds')
    event = json.loads(Path(environment['GITHUB_EVENT_PATH']).read_text(encoding='utf-8'))
    pull = event.get('pull_request', {})
    require(event.get('action') == 'closed' and pull.get('merged') is True and
            pull.get('base', {}).get('ref') == 'master' and
            pull.get('base', {}).get('repo', {}).get('full_name') == REPOSITORY,
            'Only a merged pull request on the official master may publish rebuilds')


def existing_pull_request(root, branch):
    records = json.loads(output(root, 'gh', 'pr', 'list', '--repo', REPOSITORY,
                                '--state', 'all', '--base', 'master', '--head', branch,
                                '--limit', '100', '--json',
                                'number,url,state,headRefName,baseRefName,isCrossRepository,headRepositoryOwner'))
    require(isinstance(records, list), 'Unexpected rebuild pull request response')
    matches = []
    for record in records:
        require(isinstance(record, dict), 'Unexpected rebuild pull request record')
        if (record.get('headRefName') != branch or record.get('baseRefName') != 'master' or
                record.get('isCrossRepository') is not False or
                record.get('headRepositoryOwner', {}).get('login') != 'polobread'):
            continue
        require(record.get('state') in ('OPEN', 'CLOSED', 'MERGED') and
                re.fullmatch(r'https://github.com/polobread/KeyKey/pull/[1-9][0-9]*', record.get('url', '')),
                'Invalid existing rebuild pull request')
        matches.append(record)
    # A closed review is also a decision: retrying identical generated content
    # must not reopen it or create another request. Changed content gets a new
    # fingerprint and therefore a different branch.
    return min(matches, key=lambda record: (record['state'] != 'OPEN', record['number'])) if matches else None


def remote_head(root, branch):
    value = output(root, 'git', 'ls-remote', '--heads', 'origin', f'refs/heads/{branch}')
    if not value:
        return None
    lines = value.splitlines()
    require(len(lines) == 1 and re.fullmatch(r'[a-f0-9]{40}\trefs/heads/' + re.escape(branch), lines[0]),
            'Unexpected remote branch response')
    return lines[0].split('\t')[0]


def pull_request_body(report, revision, fingerprint):
    delta = report['regression']
    return (
        f'<!-- keykey-rebuild-fingerprint: {fingerprint} -->\n\n'
        f'Source: {revision}\n\n'
        f'{report["validation_articles"]} fixed regression articles: '
        f'{delta["before"]} → {delta["after"]} actions ({delta["delta"]:+d}).\n\n'
        f'{report["reason"]}\n\n'
        f'{report["publication_reason"]}\n\n'
        'Generated files only. Manual review and merge are required; no auto-merge or CDN deployment.\n'
    )


def publish(directory, root=ROOT, environment=None):
    environment = os.environ if environment is None else environment
    report = json.loads((directory / 'build-report.json').read_text(encoding='utf-8'))
    files = json.loads((directory / 'generated-files.json').read_text(encoding='utf-8'))
    require(type(report.get('publication_needed')) is bool, 'Missing rebuild publication decision')
    if not report['publication_needed']:
        require(files == [], 'A no-op rebuild must not publish generated files')
        print(report['publication_reason'])
        return {'status': 'unchanged'}
    validate_context(environment)
    require(report.get('decision') in ('adopted', 'rejected'), 'Unknown rebuild decision')
    fingerprint = report.get('publication_fingerprint', '')
    require(re.fullmatch(r'[a-f0-9]{64}', fingerprint), 'Invalid rebuild publication fingerprint')
    files = generated_paths(root, files)
    require(files, 'A substantive rebuild must have generated files')
    require(report.get('files') == files, 'Build report and generated file list disagree')
    require(output(root, 'git', 'symbolic-ref', '--short', 'HEAD') == 'master',
            'Rebuild publication must start from checked-out master')
    revision = output(root, 'git', 'rev-parse', 'HEAD')
    require(re.fullmatch(r'[a-f0-9]{40}', revision), 'Invalid rebuilt master revision')
    # Index and worktree isolation protects against accidentally including a
    # source edit or an unrelated generated file in the bot commit.
    require(not output(root, 'git', 'diff', '--cached', '--name-only', '-z'),
            'The rebuild publication index must be empty')
    changed = set(output(root, 'git', 'diff', '--name-only', '-z', 'HEAD').split('\0')) - {''}
    untracked = set(output(root, 'git', 'ls-files', '--others', '--exclude-standard', '-z').split('\0')) - {''}
    require(changed | untracked <= set(files), 'Checkout has changes outside generated-files.json')
    run(root, 'git', 'fetch', 'origin', 'master')
    require(output(root, 'git', 'rev-parse', 'origin/master') == revision,
            'master changed during the rebuild; rerun on current master')
    branch = BRANCH_PREFIX + fingerprint
    existing = existing_pull_request(root, branch)
    if existing:
        print(f'Existing {existing["state"].lower()} rebuild review: {existing["url"]}')
        return {'status': 'existing', 'url': existing['url'], 'state': existing['state']}
    require(remote_head(root, branch) is None,
            'Rebuild branch already exists without a matching PR; review it before retrying')
    require(remote_head(root, 'master') == revision,
            'master changed during rebuild publication; rerun on current master')
    body = directory / 'pull-request.md'
    body.write_text(pull_request_body(report, revision, fingerprint), encoding='utf-8')
    run(root, 'git', 'switch', '-c', branch)
    run(root, 'git', '--literal-pathspecs', 'add', '--', *files)
    staged = set(output(root, 'git', 'diff', '--cached', '--name-only', '-z').split('\0')) - {''}
    require(staged and staged <= set(files), 'Expected only generated rebuild changes in the index')
    run(root, 'git', 'diff', '--cached', '--check')
    run(root, 'git', '-c', 'user.name=github-actions[bot]', '-c',
        'user.email=41898282+github-actions[bot]@users.noreply.github.com', 'commit', '-m',
        f'KeyKey dictionary rebuild: {report["decision"]} (30-action threshold)')
    require(remote_head(root, 'master') == revision,
            'master changed before rebuild push; rerun on current master')
    run(root, 'gh', 'auth', 'setup-git')
    run(root, 'git', 'push', 'origin', f'HEAD:refs/heads/{branch}')
    url = output(root, 'gh', 'pr', 'create', '--repo', REPOSITORY, '--base', 'master', '--head', branch,
                 '--title', f'KeyKey dictionary rebuild: {report["decision"]}', '--body-file', str(body))
    require(re.fullmatch(r'https://github.com/polobread/KeyKey/pull/[1-9][0-9]*', url),
            'Unexpected new rebuild pull request URL')
    print(url)
    return {'status': 'created', 'url': url}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    args = parser.parse_args()
    publish(args.directory)


if __name__ == '__main__':
    main()
