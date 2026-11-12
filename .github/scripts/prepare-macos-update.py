#!/usr/bin/env python3
"""Prepare signed stable macOS updates from published bytes and open a review PR."""
import argparse
import base64
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit
from urllib.request import urlopen
import zipfile

ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = 'polobread/KeyKey'
ASSET_PATH = 'keykey/releases/download'
GITHUB_ASSET_BASE = f'https://github.com/{REPOSITORY}/releases/download'
sys.path.insert(0, str(ROOT / 'update'))
import channels
import metadata

spec = importlib.util.spec_from_file_location('sync_macos_feeds', Path(__file__).with_name('sync-update-feeds.py'))
feeds = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feeds)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def api(endpoint):
    return json.loads(output('gh', 'api', f'repos/{REPOSITORY}/{endpoint}'))


def stable_version(tag):
    require(tag.startswith('v'), 'A published vX.Y.Z tag is required')
    version, channel, _ = channels.parse_version(tag[1:])
    require(channel == 'stable', 'This workflow only prepares stable macOS updates')
    return version


def tag_commit(tag):
    obj = api(f'git/ref/tags/{tag}')['object']
    for _ in range(4):
        if obj['type'] == 'commit':
            require(re.fullmatch(r'[a-f0-9]{40}', obj['sha']), 'Invalid tag commit')
            return obj['sha']
        require(obj['type'] == 'tag', 'Tag must resolve to a commit')
        obj = api('git/tags/' + obj['sha'])['object']
    raise ValueError('Tag nesting limit exceeded')


def release_record(tag):
    version = stable_version(tag)
    record = json.loads(output('gh', 'release', 'view', tag, '--repo', REPOSITORY,
                              '--json', 'tagName,isDraft,isPrerelease,publishedAt,assets'))
    require(record['tagName'] == tag and not record['isDraft'] and not record['isPrerelease'],
            'A published stable Release is required')
    return version, record


def asset_record(record, name):
    matches = [a for a in record['assets'] if a['name'] == name]
    require(len(matches) == 1 and matches[0]['size'] > 0 and
            re.fullmatch(r'sha256:[a-f0-9]{64}', matches[0].get('digest') or ''),
            f'Expected one nonempty published asset with SHA-256: {name}')
    return matches[0]


def download(tag, record, name, directory):
    asset = asset_record(record, name)
    path = directory / name
    if not path.exists():
        subprocess.run(['gh', 'release', 'download', tag, '--repo', REPOSITORY,
                        '--pattern', name, '--dir', str(directory)], check=True)
    require(path.is_file() and not path.is_symlink() and path.stat().st_size == asset['size'] and
            'sha256:' + metadata.digest(path) == asset['digest'], f'Published bytes differ: {name}')
    return path


def validate_provenance(info, record, package, version, source):
    tag = 'v' + version
    require(info.get('platform') == 'macos' and info.get('version') == version and
            info.get('release_tag') == tag and info.get('source_sha') == source == info.get('tag_sha'),
            'Build-info must match the macOS version and exact release tag commit')
    asset = asset_record(record, package.name)
    matches = [a for a in info['assets'] if a['name'] == package.name]
    checksum = metadata.digest(package)
    require(len(matches) == 1 and matches[0]['size'] == package.stat().st_size == asset['size'] and
            matches[0]['sha256'] == checksum and asset['digest'] == 'sha256:' + checksum,
            'Package, Release digest and build-info disagree')
    require(package.with_name(package.name + '.sha256').read_text(encoding='utf-8-sig').strip() ==
            f'{checksum}  {package.name}', 'Published checksum file differs')
    return checksum


def validate_run(info, source, trigger_run=None):
    match = re.fullmatch(r'https://github.com/polobread/KeyKey/actions/runs/([1-9][0-9]*)', info.get('run_url', ''))
    require(match, 'Build-info has no official Actions run')
    run = api('actions/runs/' + match[1])
    require(run.get('repository', {}).get('full_name') == REPOSITORY and
            run.get('head_repository', {}).get('full_name') == REPOSITORY and
            run.get('path') == '.github/workflows/package-macos.yml' and
            run.get('event') in ('release', 'workflow_dispatch') and
            run.get('conclusion') == 'success' and run.get('head_sha') == source and
            str(run.get('run_attempt')) == str(info.get('run_attempt')),
            'Package must originate from a successful official macOS release run')
    if trigger_run:
        require(str(run['id']) == str(trigger_run), 'Published package belongs to another workflow run')


def validate_merged_source(source, master):
    comparison = api(f'compare/{source}...{master}')
    require(comparison.get('status') in ('ahead', 'identical') and
            comparison.get('merge_base_commit', {}).get('sha') == source,
            'Release source must already belong to reviewed master')


def pinned_key():
    return json.loads((ROOT / 'update/config.json').read_text())['public_ed25519_key']


def cdn_asset_base():
    feed = json.loads((ROOT / 'update/config.json').read_text())['macos_feed_url']
    parsed = urlsplit(feed)
    require(parsed.scheme == 'https' and parsed.hostname and not parsed.username and not parsed.password and
            parsed.path == '/keykey/update/stable/macos-arm64.xml' and not parsed.query and not parsed.fragment,
            'The reviewed macOS update feed must be on the HTTPS release mirror')
    origin = f'{parsed.scheme}://{parsed.netloc}'
    base = os.environ.get('RELEASE_MIRROR_BASE_URL', origin).strip().rstrip('/')
    require(base == origin, 'RELEASE_MIRROR_BASE_URL must match the reviewed macOS CDN origin')
    return f'{base}/{ASSET_PATH}'


def asset_url(base, entry):
    return f"{base}/{entry['release_tag']}/{entry['name']}"


def proposal_entry(directory):
    document = json.loads((directory / 'proposal/metadata.json').read_text())
    return next(entry for entry in document['releases'] if entry['target'] == 'macos-arm64')


def prepare(tag, directory, trigger_run=None):
    version, record = release_record(tag)
    source = tag_commit(tag)
    base_sha = output('git', 'rev-parse', 'HEAD')
    validate_merged_source(source, base_sha)
    directory.mkdir(parents=True, exist_ok=True)
    originals = directory / 'original'
    originals.mkdir(exist_ok=True)
    name = f'chichi77-KeyKey-{version}-macos-arm64.pkg.zip'
    package = download(tag, record, name, originals)
    download(tag, record, name + '.sha256', originals)
    info_file = download(tag, record, f'chichi77-KeyKey-{version}-macos-build-info.json', originals)
    info = json.loads(info_file.read_text())
    checksum = validate_provenance(info, record, package, version, source)
    validate_run(info, source, trigger_run)
    # Verify every existing feed/metadata pair before preserving other platforms.
    feeds.channel_snapshot(ROOT / 'update/stable', 'stable')
    document = json.loads((ROOT / 'update/stable/metadata.json').read_text())
    existing = [r for r in document['releases'] if r['target'] == 'macos-arm64']
    move_to_cdn = False
    if existing:
        current = existing[0]
        new_version = tuple(map(int, version.split('.')))
        old_version = tuple(map(int, current['version'].split('.')))
        require(new_version >= old_version, 'Refusing to downgrade the macOS feed')
        if new_version == old_version:
            require(current['sha256'] == checksum and current['size'] == package.stat().st_size,
                    'Refusing different bytes for a published update version')
            require(current['release_tag'] == tag and current['source_sha'] == source,
                    'Refusing a different release source for a published update version')
            if current['url'] == asset_url(cdn_asset_base(), current):
                print('This macOS version is already in the reviewed CDN feed.')
                return False
            require(current['url'] == asset_url(GITHUB_ASSET_BASE, current),
                    'Only the reviewed GitHub copy can be moved to the CDN')
            move_to_cdn = True
    plan = dict(version=version, release_tag=tag, source_sha=source, sha256=checksum,
                size=package.stat().st_size, file=str(package.resolve()),
                base_sha=base_sha, move_to_cdn=move_to_cdn)
    (directory / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
    print(f'Published source and bytes verified: {tag}, SHA-256 {checksum}')
    return True


def package_info(package, version):
    """Check signed payload identity, public key and actual minimum macOS version."""
    metadata.verify_platform_package(dict(target='macos-arm64', version=version, file=str(package)))
    with tempfile.TemporaryDirectory(prefix='keykey-macos-payload-') as scratch:
        scratch = Path(scratch)
        with zipfile.ZipFile(package) as archive:
            names = [n for n in archive.namelist() if '/' not in n and n.endswith('.pkg')]
            require(len(names) == 1, 'Expected one root macOS package')
            flat = scratch / 'release.pkg'
            with archive.open(names[0]) as src, flat.open('wb') as dst:
                shutil.copyfileobj(src, dst)
        expanded = scratch / 'expanded'
        subprocess.run(['pkgutil', '--expand-full', str(flat), str(expanded)], check=True)
        apps = list(expanded.glob('*/Payload/Library/Input Methods/chichi77 KeyKey.app'))
        require(len(apps) == 1, 'Expected the fixed-location KeyKey app payload')
        app = apps[0]
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        require(info.get('CFBundleIdentifier') == 'io.github.polobread.inputmethod.chichi77' and
                info.get('CFBundleVersion') == info.get('CFBundleShortVersionString') == version and
                info.get('SUPublicEDKey') == pinned_key(), 'App identity/version/update public key differs')
        minimum = info['LSMinimumSystemVersion']
        require(re.fullmatch(r'\d+\.\d+(?:\.\d+)?', minimum), 'Invalid minimum macOS version')
        for name in ('Preferences', 'PhraseEditor', 'InstallerHelp'):
            helper = plistlib.loads((app / f'Contents/SharedSupport/{name}.app/Contents/Info.plist').read_bytes())
            require(helper.get('CFBundleVersion') == helper.get('CFBundleShortVersionString') == version,
                    f'{name} version differs')
        require('arm64' in output('lipo', '-archs', str(app / 'Contents/MacOS/chichi77 KeyKey')).split(),
                'The update does not contain arm64')
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        subprocess.run(['spctl', '--assess', '--type', 'execute', '--verbose=2', str(app)], check=True)
        return minimum if minimum.count('.') == 2 else minimum + '.0'


def merged_document(document, entry):
    result = dict(document)
    result['generated_at'] = datetime.now(timezone.utc).isoformat()
    result['releases'] = [r for r in document['releases'] if r['target'] != 'macos-arm64'] + [entry]
    return result


def sign_candidate(directory, key, openssl):
    require(not key.is_symlink() and key.is_file(), 'A local Ed25519 key file is required')
    # Never allow a committed/staged private key to enter signing or PR preparation.
    tracked = subprocess.run(['git', 'ls-files', '--error-unmatch', str(key.resolve())],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    require(tracked.returncode != 0, 'Private key must not be tracked or staged')
    require(metadata.public_key(key, openssl) == pinned_key(), 'Private key does not match reviewed public key')
    plan = json.loads((directory / 'plan.json').read_text())
    package = Path(plan['file'])
    require(metadata.digest(package) == plan['sha256'] and package.stat().st_size == plan['size'], 'Package changed')
    require(output('git', 'rev-parse', 'HEAD') == plan['base_sha'], 'Checkout changed; prepare again')
    minimum = package_info(package, plan['version'])
    entry = dict(target='macos-arm64', version=plan['version'], release_tag=plan['release_tag'],
                 source_sha=plan['source_sha'], tag_sha=plan['source_sha'], file=str(package),
                 minimum_system_version=minimum,
                 notes=f"macOS 琦琦輸入法 {plan['version']} 正式更新。安裝需要管理員確認；完成後請選取琦琦並試打。")
    manifest = dict(schema_version=1, channel='stable', releases=[entry])
    generated = directory / 'signed'
    # This performs Gatekeeper installer assessment, stapled notarization and package-version verification.
    result = metadata.build(manifest, key, cdn_asset_base(), generated, pinned_key(), openssl)
    proposal = directory / 'proposal'
    proposal.mkdir()
    for name, data in feeds.channel_snapshot(ROOT / 'update/stable', 'stable'):
        (proposal / name).write_bytes(data)
    original = json.loads((proposal / 'metadata.json').read_text())
    entry = result['releases'][0]
    if plan['move_to_cdn']:
        previous = proposal_entry(directory)
        require(previous['url'] == asset_url(GITHUB_ASSET_BASE, entry) and
                all(previous[field] == entry[field] for field in
                    ('source_sha', 'tag_sha', 'sha256', 'size', 'ed25519_signature')),
                'The existing macOS announcement no longer matches the reviewed copy')
        entry = dict(previous, url=entry['url'])
    (proposal / 'macos-arm64.xml').write_bytes(metadata.appcast(entry))
    merged = merged_document(original, entry)
    path = proposal / 'metadata.json'
    path.write_text(json.dumps(merged, ensure_ascii=False, sort_keys=True, indent=2) + '\n', encoding='utf-8')
    signature = metadata.sign(path, key, openssl)
    metadata.verify(path, signature, pinned_key(), openssl)
    (proposal / 'metadata.json.sig').write_text(signature + '\n', encoding='ascii')
    feeds.channel_snapshot(proposal, 'stable')
    print('Signed candidate prepared; other platform entries and XML bytes preserved.')


def verify_remote(entry, openssl):
    with tempfile.TemporaryDirectory(prefix='keykey-update-readback-') as scratch:
        path = Path(scratch) / entry['name']
        with urlopen(entry['url'], timeout=60) as response, path.open('wb') as stream:
            require(urlsplit(response.geturl()).scheme == 'https', 'Asset redirected away from HTTPS')
            size = 0
            for chunk in iter(lambda: response.read(1024 * 1024), b''):
                size += len(chunk)
                require(size <= entry['size'], 'Remote asset exceeds expected size')
                stream.write(chunk)
        require(size == entry['size'] and metadata.digest(path) == entry['sha256'], 'Remote asset bytes differ')
        metadata.verify(path, entry['ed25519_signature'], pinned_key(), openssl)


def stage_cdn_copy(path, entry, bucket, distribution):
    key = f"{ASSET_PATH}/{entry['release_tag']}/{entry['name']}"
    checksum = base64.b64encode(bytes.fromhex(entry['sha256'])).decode('ascii')
    upload = subprocess.run(['aws', 's3api', 'put-object', '--bucket', bucket, '--key', key,
                             '--body', str(path), '--if-none-match', '*', '--checksum-algorithm', 'SHA256',
                             '--checksum-sha256', checksum, '--content-type', 'application/octet-stream',
                             '--cache-control', 'public,max-age=0,s-maxage=31536000,must-revalidate',
                             '--no-cli-pager', '--output', 'json'], capture_output=True, text=True)
    if upload.returncode and '(PreconditionFailed)' not in upload.stderr:
        raise subprocess.CalledProcessError(upload.returncode, upload.args, stderr=upload.stderr)
    if not upload.returncode:
        require(json.loads(upload.stdout).get('ChecksumSHA256') == checksum, 'S3 upload checksum mismatch')
    with tempfile.TemporaryDirectory(prefix='keykey-update-s3-readback-') as scratch:
        fetched = Path(scratch) / entry['name']
        feeds.aws('s3api', 'get-object', '--bucket', bucket, '--key', key, '--checksum-mode', 'ENABLED', str(fetched))
        require(fetched.stat().st_size == entry['size'] and metadata.digest(fetched) == entry['sha256'],
                'Existing S3 copy differs; never overwrite it')
    invalidation = feeds.aws('cloudfront', 'create-invalidation', '--distribution-id', distribution,
                             '--paths', '/' + key)['Invalidation']['Id']
    subprocess.run(['aws', 'cloudfront', 'wait', 'invalidation-completed', '--distribution-id', distribution,
                    '--id', invalidation, '--no-cli-pager'], check=True)


def stage_asset(directory, openssl):
    feeds.channel_snapshot(directory / 'proposal', 'stable')
    plan = json.loads((directory / 'plan.json').read_text())
    _, release = release_record(plan['release_tag'])
    require(tag_commit(plan['release_tag']) == plan['source_sha'], 'Release tag moved')
    original = asset_record(release, f"chichi77-KeyKey-{plan['version']}-macos-arm64.pkg.zip")
    require(original['digest'] == 'sha256:' + plan['sha256'] and original['size'] == plan['size'],
            'Published original changed after preparation')
    entry = proposal_entry(directory)
    require(entry['url'] == asset_url(cdn_asset_base(), entry) and entry['release_tag'] == plan['release_tag'] and
            entry['source_sha'] == plan['source_sha'], 'Expected a verified macOS CDN announcement')
    bucket = os.environ.get('RELEASE_MIRROR_BUCKET', '').strip()
    distribution = os.environ.get('RELEASE_MIRROR_DISTRIBUTION_ID', '').strip()
    require(re.fullmatch(r'[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]', bucket) and
            re.fullmatch(r'[A-Z0-9]+', distribution), 'A valid release mirror bucket and distribution are required')
    path = directory / 'signed/packages' / entry['name']
    require(path.is_file() and not path.is_symlink() and metadata.digest(path) == entry['sha256'] == plan['sha256'] and
            path.stat().st_size == entry['size'] == plan['size'], 'Signed copy differs from verified original')
    metadata.verify(path, entry['ed25519_signature'], pinned_key(), openssl)
    existing = [a for a in release['assets'] if a['name'] == entry['name']]
    if existing:
        asset = asset_record(release, entry['name'])
        require(asset['digest'] == 'sha256:' + entry['sha256'] and asset['size'] == entry['size'],
                'Existing immutable asset differs; never overwrite it')
    else:
        subprocess.run(['gh', 'release', 'upload', plan['release_tag'], '--repo', REPOSITORY, str(path)], check=True)
    verify_remote(dict(entry, url=asset_url(GITHUB_ASSET_BASE, entry)), openssl)
    stage_cdn_copy(path, entry, bucket, distribution)
    verify_remote(entry, openssl)
    print('Immutable GitHub and CDN copies verified by download, SHA-256 and Ed25519.')


def open_pr(directory, openssl):
    require(os.environ.get('GITHUB_REF') == 'refs/heads/master' and
            os.environ.get('GITHUB_REPOSITORY') == REPOSITORY and
            os.environ.get('GITHUB_EVENT_NAME') in ('workflow_dispatch', 'workflow_run'),
            'Automatic feed PR creation is restricted to reviewed master')
    plan = json.loads((directory / 'plan.json').read_text())
    require(output('git', 'rev-parse', 'HEAD') == plan['base_sha'] and
            output('git', 'ls-remote', 'origin', 'refs/heads/master').split()[0] == plan['base_sha'],
            'Master advanced; rerun to preserve the latest platform metadata')
    feeds.verify_assets(directory / 'proposal', 'stable')
    entry = proposal_entry(directory)
    require(entry['url'] == asset_url(cdn_asset_base(), entry), 'Expected a macOS CDN announcement')
    verify_remote(dict(entry, url=asset_url(GITHUB_ASSET_BASE, entry)), openssl)
    branch = f"codex/macos-update-{plan['release_tag']}"
    if plan['move_to_cdn']:
        branch += '-cdn'
    require(not output('git', 'ls-remote', 'origin', 'refs/heads/' + branch),
            'Update branch already exists; review the existing PR instead of overwriting it')
    subprocess.run(['git', 'switch', '-c', branch], check=True)
    names = ['macos-arm64.xml', 'metadata.json', 'metadata.json.sig']
    paths = []
    for name in names:
        target = ROOT / 'update/stable' / name
        target.write_bytes((directory / 'proposal' / name).read_bytes())
        paths.append(str(target))
    subprocess.run(['git', 'diff', '--check'], check=True)
    subprocess.run(['git', 'add', '--', *paths], check=True)
    subprocess.run(['git', '-c', 'user.name=github-actions[bot]', '-c',
                    'user.email=41898282+github-actions[bot]@users.noreply.github.com',
                    'commit', '-m', f"Announce macOS {plan['version']} in the stable update feed"], check=True)
    subprocess.run(['git', 'push', 'origin', f'HEAD:refs/heads/{branch}'], check=True)
    body = directory / 'pull-request.md'
    body.write_text(f"讓已安裝舊版的 macOS 使用者看見 {plan['version']} 正式更新。\n\n"
                    f"沿用已發布的 {plan['release_tag']} 安裝包，未重新建置。核對原 Release digest、checksum、"
                    "build-info、成功的官方建置來源、Apple 簽章、公證與套件版號後，產生 Ed25519 更新簽章。\n\n"
                    f"SHA-256：`{plan['sha256']}`。保留其他平台公告與 metadata。AWS CDN 與 GitHub 的內容位址副本已上傳並回讀驗證。\n\n"
                    "維護者 review／merge 後才由 Sync Update Feeds to CDN 部署；本工作不安裝更新、不合併 PR。\n",
                    encoding='utf-8')
    subprocess.run(['gh', 'pr', 'create', '--repo', REPOSITORY, '--base', 'master', '--head', branch,
                    '--title', f"公告 macOS {plan['version']} 正式更新", '--body-file', str(body)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['prepare', 'sign', 'stage-asset', 'open-pr'])
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--tag')
    parser.add_argument('--trigger-run')
    parser.add_argument('--key', type=Path)
    parser.add_argument('--openssl', default=os.environ.get('KEYKEY_TEST_OPENSSL', 'openssl'))
    args = parser.parse_args()
    os.environ['KEYKEY_TEST_OPENSSL'] = args.openssl
    if args.command == 'prepare':
        needed = prepare(args.tag or '', args.directory, args.trigger_run)
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
                stream.write(f'needed={str(needed).lower()}\n')
    elif args.command == 'sign':
        require(args.key is not None, '--key is required for signing')
        sign_candidate(args.directory, args.key, args.openssl)
    elif args.command == 'stage-asset':
        stage_asset(args.directory, args.openssl)
    else:
        open_pr(args.directory, args.openssl)


if __name__ == '__main__':
    main()
