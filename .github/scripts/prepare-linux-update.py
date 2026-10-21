#!/usr/bin/env python3
"""Verify published Linux packages and open a notification-only stable feed PR."""
import argparse
import base64
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
from urllib.parse import quote
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = 'polobread/KeyKey'
CDN = 'https://download.aws.polobread.com/keykey/releases/download'
sys.path.insert(0, str(ROOT / 'update'))
sys.path.insert(0, str(ROOT / 'Source/Loaders/Linux-IME/tools'))
import channels
import update_notify as updates

spec = importlib.util.spec_from_file_location('linux_release_assets', Path(__file__).with_name('release-assets.py'))
assets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assets)
require = assets.require
output = assets.output
api = assets.recovery_api


def download(tag, name, directory, published):
    matches = [entry for entry in published['assets'] if entry['name'] == name]
    require(len(matches) == 1 and matches[0]['size'] > 0 and
            re.fullmatch(r'sha256:[a-f0-9]{64}', matches[0].get('digest') or ''),
            f'Expected one published Linux asset with size/digest: {name}')
    path = directory / name
    require(not path.is_symlink(), 'Published Linux asset must not be a symlink')
    if not path.exists():
        return assets.recovery_download(tag, name, directory, published)
    require(path.is_file() and not path.is_symlink() and path.stat().st_size == matches[0]['size'] and
            'sha256:' + assets.digest(path) == matches[0]['digest'], f'Published Linux bytes differ: {name}')
    return path


def version_for_tag(tag):
    require(re.fullmatch(r'v' + channels.VERSION, tag or ''), 'A stable vX.Y.Z tag is required')
    return channels.parse_version(tag[1:])[0]


def tag_commit(tag):
    obj = api(f'git/ref/tags/{tag}')['object']
    for _ in range(4):
        if obj['type'] == 'commit':
            require(re.fullmatch(r'[a-f0-9]{40}', obj['sha']), 'Invalid release commit')
            return obj['sha']
        require(obj['type'] == 'tag', 'Tag must resolve to a commit')
        obj = api('git/tags/' + obj['sha'])['object']
    raise ValueError('Tag nesting limit exceeded')


def verify_source(tag, source, master):
    comparison = api(f'compare/{source}...{master}')
    require(comparison.get('status') in ('ahead', 'identical') and
            comparison.get('merge_base_commit', {}).get('sha') == source,
            'Linux release source must belong to reviewed master')
    record = api(f'contents/Source/Loaders/Linux-IME/CMakeLists.txt?ref={source}')
    cmake = base64.b64decode(record['content']).decode('utf-8')
    version = version_for_tag(tag)
    require(re.search(r'^project\(KeyKeyLinux VERSION ' + re.escape(version) + r' LANGUAGES', cmake, re.M),
            'Release tag does not contain the announced Linux product version')


def verify_run(info, source, trigger_run=None):
    match = re.fullmatch(r'https://github.com/polobread/KeyKey/actions/runs/([1-9][0-9]*)', info.get('run_url', ''))
    require(match, 'Build-info must name an official Linux publication run')
    run = api('actions/runs/' + match[1])
    require(run.get('repository', {}).get('full_name') == REPOSITORY and
            run.get('head_repository', {}).get('full_name') == REPOSITORY and
            run.get('path') == '.github/workflows/linux-ci.yml' and
            run.get('event') in ('release', 'workflow_dispatch') and
            run.get('status') == 'completed' and run.get('conclusion') == 'success' and
            run.get('head_sha') == source and str(run.get('run_attempt')) == str(info.get('run_attempt')),
            'Linux publication must originate from a successful official tag-source run')
    if trigger_run:
        require(str(run['id']) == str(trigger_run), 'Published Linux assets belong to another workflow run')
    listing = api(f"actions/runs/{run['id']}/attempts/{run['run_attempt']}/jobs?per_page=100")
    require(listing['total_count'] <= 100, 'Unexpected Linux job count')
    jobs = listing['jobs']
    required = {'Full Ubuntu 24.04 build, packages, and GTK3/GTK4/Qt6 X11 E2E',
                'Full Ubuntu 22.04 minimum API build and package lifecycle',
                'Publish Ubuntu 24.04 packages to the GitHub Release'}
    for name in required:
        matches = [job for job in jobs if job['name'] == name]
        require(len(matches) == 1 and matches[0]['conclusion'] == 'success', f'Linux release gate did not pass: {name}')
    build = next(job for job in jobs if job['name'].startswith('Full Ubuntu 24.04'))
    lifecycle = [step for step in build['steps'] if step['name'] ==
                 'Test package install, upgrade, removal, reinstall, and X11 typing']
    require(len(lifecycle) == 1 and lifecycle[0]['conclusion'] == 'success', 'Linux package lifecycle/X11 gate did not pass')


def deb_control(path):
    """Read bounded Debian control metadata without extracting or executing payloads."""
    raw = path.read_bytes()
    require(raw[:8] == b'!<arch>\n', 'Not a Debian ar package')
    offset, controls = 8, []
    while offset < len(raw):
        header = raw[offset:offset + 60]
        require(len(header) == 60 and header[58:60] == b'`\n', 'Invalid Debian ar header')
        size = int(header[48:58])
        require(0 <= size <= len(raw) - offset - 60, 'Invalid Debian ar member size')
        name = header[:16].decode('ascii').strip().rstrip('/')
        if name.startswith('control.tar'):
            require(size <= 1024 * 1024, 'Debian control archive is too large')
            with tarfile.open(fileobj=io.BytesIO(raw[offset + 60:offset + 60 + size]), mode='r:*') as bundle:
                members = [member for member in bundle if member.name.removeprefix('./') == 'control']
                require(len(members) == 1 and members[0].isfile() and 0 < members[0].size <= 65536,
                        'Expected one bounded Debian control file')
                controls.append(bundle.extractfile(members[0]).read().decode('utf-8'))
        offset += 60 + size + size % 2
    require(len(controls) == 1, 'Expected one Debian control archive')
    fields = {}
    for line in controls[0].splitlines():
        if line and not line[0].isspace():
            key, separator, value = line.partition(':')
            require(separator and key not in fields, 'Invalid or duplicate Debian control field')
            fields[key] = value.strip()
    return fields


def verify_packages(directory, published, info, tag, source):
    version = version_for_tag(tag)
    require(all(info.get(key) == value for key, value in dict(platform='linux', version=version,
            release_tag=tag, release_version=version, update_channel='stable', source_sha=source, tag_sha=source).items()),
            'Linux build-info must match the stable version and exact tag source')
    paths = assets.verified_assets(directory, 'linux', version)
    expected = [dict(name=path.name, size=path.stat().st_size, sha256=assets.digest(path)) for path in paths]
    require(info.get('assets') == expected, 'Linux build-info package hashes differ')
    for path in paths:
        # Recheck the GitHub digest and size before trusting cached package bytes.
        download(tag, path.name, directory, published)
        assets.verify_cdn_bytes(f'{CDN}/{tag}/{quote(path.name, safe="")}', path)
        if path.suffix == '.deb':
            fields = deb_control(path)
            if path.name.startswith('fcitx5-chichi77-keykey_'):
                package, architecture, package_version = 'fcitx5-chichi77-keykey', 'amd64', f'{version}-1+ubuntu24.04'
            elif path.name.startswith('chichi77-keykey-data_'):
                package, architecture, package_version = 'chichi77-keykey-data', 'all', f'{version}-1+ubuntu24.04'
            else:
                package, architecture = 'gnome-shell-extension-keykey-kimpanel', 'all'
                package_version = path.name.removeprefix(package + '_').removesuffix('_all.deb')
            require(fields.get('Package') == package and fields.get('Version') == package_version and
                    fields.get('Architecture') == architecture, 'Debian package identity/version/architecture differs')
    return expected


def updated_feed(original, version):
    entries = updates.parse_feed(original, 'stable')
    newest = max((updates.version_key(entry['version']) for entry in entries), default=None)
    incoming = updates.version_key(version)
    require(newest is None or incoming >= newest, 'Refusing to downgrade the Linux stable feed')
    if newest == incoming:
        current = next(entry for entry in entries if entry['version'] == version)
        require(current['linux_architectures'] == ['amd64'], 'Existing same-version Linux announcement differs')
        return None
    ET.register_namespace('sparkle', updates.SPARKLE)
    ET.register_namespace('keykey', updates.UNIX)
    document = ET.fromstring(original)
    channel = document.find('channel')
    channel.find('description').text = ('Linux／FreeBSD 共用每週更新通知。Linux 請從官方發行頁下載並透過套件管理器安裝；'
        'FreeBSD 請透過 ports／pkg 更新，套件可能較晚上架。本 feed 只通知新版，不下載或自動安裝套件。')
    item = ET.Element('item')
    ET.SubElement(item, 'title').text = f'琦琦輸入法 {version} 正式更新'
    for field in ('version', 'shortVersionString'):
        ET.SubElement(item, f'{{{updates.SPARKLE}}}{field}').text = version
    ET.SubElement(item, 'link').text = f'{updates.RELEASES}/tag/v{version}'
    ET.SubElement(item, f'{{{updates.UNIX}}}linuxArchitecture').text = 'amd64'
    ET.SubElement(item, 'description').text = (f'琦琦輸入法 {version} 已發布。功能與操作方式請見官方發行頁。'
        'Linux 已提供 Ubuntu 24.04 amd64 套件及共用詞庫，請透過套件管理器安裝。'
        'FreeBSD 同步接收本公告，請透過 ports／pkg 更新，套件可能較晚上架。')
    channel.insert(next((i for i, element in enumerate(channel) if element.tag == 'item'), len(channel)), item)
    ET.indent(document, space='  ')
    result = ET.tostring(document, encoding='utf-8', xml_declaration=True) + b'\n'
    updates.parse_feed(result, 'stable')
    return result


def prepare(tag, directory, trigger_run=None):
    version = version_for_tag(tag)
    published = api(f'releases/tags/{tag}')
    require(published['tag_name'] == tag and not published['draft'] and not published['prerelease'],
            'A published stable Linux release is required')
    source, master = tag_commit(tag), output('git', 'rev-parse', 'HEAD')
    verify_source(tag, source, master)
    directory.mkdir(parents=True, exist_ok=True)
    originals = directory / 'original'
    originals.mkdir(exist_ok=True)
    info_path = download(tag, f'chichi77-KeyKey-{version}-linux-build-info.json', originals, published)
    info = json.loads(info_path.read_text())
    assets.verify_cdn_bytes(f'{CDN}/{tag}/{info_path.name}', info_path)
    verify_run(info, source, trigger_run)
    names = [entry['name'] for entry in info['assets']]
    require(len(names) == 5 and len(set(names)) == 5 and all(
        name == Path(name).name and '/' not in name and '\\' not in name and
        re.fullmatch(r'[A-Za-z0-9.+_-]+', name) for name in names), 'Unsafe or unexpected Linux asset names')
    for name in names:
        download(tag, name, originals, published)
    verified = verify_packages(originals, published, info, tag, source)
    original = (ROOT / 'update/stable/unix-fcitx5.xml').read_bytes()
    candidate = updated_feed(original, version)
    if candidate is None:
        print('This Linux version is already in the reviewed stable feed.')
        return False
    proposal = directory / 'proposal'
    proposal.mkdir(exist_ok=True)
    (proposal / 'unix-fcitx5.xml').write_bytes(candidate)
    plan = dict(version=version, release_tag=tag, source_sha=source, base_sha=master,
                run_url=info['run_url'], run_attempt=info['run_attempt'], assets=verified,
                build_info_sha256=assets.digest(info_path),
                feed_sha256=assets.digest(proposal / 'unix-fcitx5.xml'))
    (directory / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
    return True


def revalidate(directory, plan):
    published = api(f"releases/tags/{plan['release_tag']}")
    require(published['tag_name'] == plan['release_tag'] and not published['draft'] and not published['prerelease'],
            'Published Linux release changed')
    originals = directory / 'original'
    info_file = download(plan['release_tag'], f"chichi77-KeyKey-{plan['version']}-linux-build-info.json", originals, published)
    require(assets.digest(info_file) == plan['build_info_sha256'], 'Linux build-info changed')
    info = json.loads(info_file.read_text())
    verify_run(info, plan['source_sha'])
    assets.verify_cdn_bytes(f"{CDN}/{plan['release_tag']}/{info_file.name}", info_file)
    require(verify_packages(originals, published, info, plan['release_tag'], plan['source_sha']) == plan['assets'],
            'Linux package evidence changed')


def open_pr(directory):
    require(os.environ.get('GITHUB_REF') == 'refs/heads/master' and
            os.environ.get('GITHUB_REPOSITORY') == REPOSITORY and
            os.environ.get('GITHUB_EVENT_NAME') in ('workflow_dispatch', 'workflow_run'),
            'Automatic Linux update PR creation requires reviewed official master')
    plan = json.loads((directory / 'plan.json').read_text())
    require(version_for_tag(plan['release_tag']) == plan['version'], 'Linux plan version differs from release tag')
    require(tag_commit(plan['release_tag']) == plan['source_sha'], 'Linux release tag moved')
    require(output('git', 'rev-parse', 'HEAD') == plan['base_sha'] and
            output('git', 'ls-remote', 'origin', 'refs/heads/master').split()[0] == plan['base_sha'],
            'Master advanced; rerun Linux update preparation')
    revalidate(directory, plan)
    candidate = directory / 'proposal/unix-fcitx5.xml'
    require(assets.digest(candidate) == plan['feed_sha256'], 'Prepared Linux announcement changed')
    updates.parse_feed(candidate.read_bytes(), 'stable')
    branch = f"codex/linux-update-{plan['release_tag']}"
    require(not output('git', 'ls-remote', 'origin', 'refs/heads/' + branch),
            'Linux update branch already exists; review the existing PR instead of overwriting it')
    subprocess.run(['git', 'switch', '-c', branch], check=True)
    target = ROOT / 'update/stable/unix-fcitx5.xml'
    target.write_bytes(candidate.read_bytes())
    subprocess.run(['git', 'diff', '--check'], check=True)
    subprocess.run(['git', 'add', '--', str(target)], check=True)
    subprocess.run(['git', '-c', 'user.name=github-actions[bot]', '-c',
        'user.email=41898282+github-actions[bot]@users.noreply.github.com', 'commit', '-m',
        f"Announce Linux and FreeBSD {plan['version']} stable update"], check=True)
    subprocess.run(['git', 'push', 'origin', f'HEAD:refs/heads/{branch}'], check=True)
    body = directory / 'pull-request.md'
    body.write_text(f"公告 Linux／FreeBSD {plan['version']} 正式更新。\n\n"
        f"已核對 tag/source `{plan['source_sha']}` 的 Linux 產品版號、成功的官方發布工作 "
        f"{plan['run_url']}（attempt {plan['run_attempt']}）、套件生命週期與 X11 gate。\n\n"
        "GitHub／CDN 的套件、SHA256SUMS 與 build-info 均回讀驗證；DEB control 版本與架構一致。"
        "只宣告 Ubuntu 24.04 amd64；FreeBSD 同步通知，提示透過 ports／pkg 更新且套件可能較晚上架。\n\n"
        + '\n'.join(f"- `{entry['name']}`：SHA-256 `{entry['sha256']}`（{entry['size']} bytes）"
                    for entry in plan['assets']) + '\n\n'
        "維護者 review／merge 後才由 Sync Update Feeds to CDN 部署；不自動合併或安裝。\n")
    subprocess.run(['gh', 'pr', 'create', '--repo', REPOSITORY, '--base', 'master', '--head', branch,
        '--title', f"公告 Linux／FreeBSD {plan['version']} 正式更新", '--body-file', str(body)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['prepare', 'open-pr'])
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--tag')
    parser.add_argument('--trigger-run')
    args = parser.parse_args()
    if args.command == 'prepare':
        needed = prepare(args.tag, args.directory, args.trigger_run)
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
                stream.write(f'needed={str(needed).lower()}\n')
    else:
        open_pr(args.directory)


if __name__ == '__main__':
    main()
