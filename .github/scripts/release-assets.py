#!/usr/bin/env python3
"""Resolve a published release and replace only one platform's verified assets."""
import argparse
import base64
import hashlib
import json
import mimetypes
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import zipfile
from urllib.parse import quote, urlsplit
from urllib.request import urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "update"))
import channels


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def release_tag(event, event_tag, requested, version):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("version must be x.y.z")
    if event == "release":
        tag = event_tag
        if not tag:
            raise ValueError("release event is missing its tag")
    elif event == "workflow_dispatch":
        tag = requested.strip()
    else:
        raise ValueError(f"unsupported publishing event: {event}")
    channels.release_version(tag, version)
    return tag


def verify_release(tag, repository):
    release = json.loads(output("gh", "release", "view", tag, "--repo", repository,
                                "--json", "tagName,isDraft,isPrerelease,url"))
    if release["tagName"] != tag or release["isDraft"]:
        raise ValueError("publish the matching GitHub Release before uploading assets")
    expected_beta = channels.parse_version(tag[1:])[1] == "beta"
    if release.get("isPrerelease", False) != expected_beta:
        raise ValueError("beta tags require a GitHub Pre-release; stable tags require a full release")
    return release["url"]


def tag_commit(tag):
    # Fetch only the remote tag into FETCH_HEAD; never create or move a tag.
    subprocess.run(["git", "fetch", "--no-tags", "--depth=1", "origin", f"refs/tags/{tag}"], check=True)
    return output("git", "rev-parse", "FETCH_HEAD^{commit}")


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def verified_assets(directory, platform, version):
    prefix = f"chichi77-KeyKey-{version}"
    if platform == "macos":
        packages = [f"{prefix}-macos-arm64.pkg.zip"]
    elif platform == "windows":
        packages = [f"{prefix}-windows-x64.zip", f"{prefix}-windows-x86.zip",
                    f"{prefix}-windows-x64-setup.unsigned.exe"]
    else:
        panels = sorted(directory.glob("gnome-shell-extension-keykey-kimpanel_*+ubuntu24.04_all.deb"))
        if len(panels) != 1:
            raise ValueError("expected exactly one Ubuntu 24.04 GNOME panel package")
        panel = panels[0].name
        packages = [f"chichi77-keykey-data_{version}-1+ubuntu24.04_all.deb",
                    f"fcitx5-chichi77-keykey_{version}-1+ubuntu24.04_amd64.deb",
                    panel, panel.removesuffix("_all.deb") + "_source.tar.gz"]
    checksums = ["SHA256SUMS"] if platform == "linux" else [name + ".sha256" for name in packages]
    paths = [directory / name for name in packages + checksums]
    if any(not path.is_file() or path.stat().st_size == 0 for path in paths):
        raise ValueError("release package or checksum is missing/empty")
    expected = {}
    for name in checksums:
        for line in (directory / name).read_text(encoding="utf-8-sig").splitlines():
            match = re.fullmatch(r"([0-9a-fA-F]{64}) [ *](.+)", line)
            if not match:
                raise ValueError(f"invalid checksum in {name}")
            checksum, filename = match.groups()
            if filename.startswith("./"):
                filename = filename[2:]
            if filename not in packages or filename in expected:
                raise ValueError(f"unexpected or duplicate checksum filename: {filename}")
            expected[filename] = checksum.lower()
    if set(expected) != set(packages):
        raise ValueError("checksums must cover exactly this platform's packages")
    for name in packages:
        if digest(directory / name) != expected[name]:
            raise ValueError(f"checksum mismatch: {name}")
    return paths


def mirror(platform, version, directory):
    tag = os.environ["RELEASE_TAG"]
    release_tag("workflow_dispatch", "", tag, version)
    bucket = os.environ["RELEASE_MIRROR_BUCKET"].strip()
    if not bucket or "/" in bucket:
        raise ValueError("RELEASE_MIRROR_BUCKET must be an S3 bucket name")
    distribution_id = os.environ["RELEASE_MIRROR_DISTRIBUTION_ID"].strip()
    if not distribution_id:
        raise ValueError("RELEASE_MIRROR_DISTRIBUTION_ID is required")

    assets = verified_assets(directory, platform, version)
    info = directory / f"chichi77-KeyKey-{version}-{platform}-build-info.json"
    if not info.is_file() or info.stat().st_size == 0:
        raise ValueError("build info is missing/empty; publish the GitHub Release assets first")
    metadata = json.loads(info.read_text(encoding="utf-8"))
    if metadata.get("platform") != platform or metadata.get("version") != version \
            or metadata.get("release_tag") != tag:
        raise ValueError("build info does not match the mirror target")

    mirrored = [*assets, info]
    prefix = f"keykey/releases/download/{tag}"
    for path in mirrored:
        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        subprocess.run([
            "aws", "s3", "cp", str(path), f"s3://{bucket}/{prefix}/{path.name}",
            "--only-show-errors", "--checksum-algorithm", "SHA256",
            "--cache-control", "public,max-age=0,s-maxage=31536000,must-revalidate",
            "--content-type", content_type,
        ], check=True)

    invalidation_paths = [f"/{prefix}/{path.name}" for path in mirrored]
    subprocess.run([
        "aws", "cloudfront", "create-invalidation",
        "--distribution-id", distribution_id,
        "--paths", *invalidation_paths,
        "--no-cli-pager", "--output", "json",
    ], check=True)

    base_url = os.environ.get("RELEASE_MIRROR_BASE_URL", "").rstrip("/")
    with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as stream:
        stream.write(f"Mirrored {platform} assets to `s3://{bucket}/{prefix}/` and "
                     f"invalidated their CloudFront paths.\n\n")
        if base_url:
            stream.write("\n".join(
                f"- [{path.name}]({base_url}/{prefix}/{quote(path.name, safe='')})" for path in mirrored) + "\n")


def resolve(version):
    tag = release_tag(os.environ["GITHUB_EVENT_NAME"], os.environ.get("EVENT_RELEASE_TAG", ""),
                      os.environ.get("REQUESTED_RELEASE_TAG", ""), version)
    source_sha = output("git", "rev-parse", "HEAD")
    target_sha = ""
    if tag:
        verify_release(tag, os.environ["GITHUB_REPOSITORY"])
        target_sha = tag_commit(tag)
        if os.environ["GITHUB_EVENT_NAME"] == "release" and source_sha != target_sha:
            raise ValueError("automatic release build must use the published tag's commit")
        if channels.parse_version(tag[1:])[1] == "beta" and source_sha != target_sha:
            raise ValueError("beta packages must be built from the beta tag commit")
    values = dict(release_tag=tag, publish_release=str(bool(tag)).lower(),
                  source_sha=source_sha, tag_sha=target_sha,
                  release_version=channels.release_version(tag, version),
                  update_channel=channels.parse_version(channels.release_version(tag, version))[1])
    with Path(os.environ["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as stream:
        for key, value in values.items():
            stream.write(f"{key}={value}\n")


def publish(platform, version, directory):
    tag = os.environ["RELEASE_TAG"]
    release_tag("workflow_dispatch", "", tag, version)
    if not tag:
        raise ValueError("publishing requires a release tag")
    repository = os.environ["GITHUB_REPOSITORY"]
    url = verify_release(tag, repository)
    source_sha = output("git", "rev-parse", "HEAD")
    target_sha = tag_commit(tag)
    if source_sha != os.environ["BUILD_SOURCE_SHA"] or target_sha != os.environ["RELEASE_TAG_SHA"]:
        raise ValueError("build source or release tag changed since validation")
    if channels.parse_version(tag[1:])[1] == "beta" and source_sha != target_sha:
        raise ValueError("beta packages must be built from the beta tag commit")
    assets = verified_assets(directory, platform, version)
    info = directory / f"chichi77-KeyKey-{version}-{platform}-build-info.json"
    run_url = f"{os.environ['GITHUB_SERVER_URL']}/{repository}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
    info.write_text(json.dumps(dict(platform=platform, version=version, release_tag=tag,
        release_version=channels.release_version(tag, version),
        update_channel=channels.parse_version(tag[1:])[1],
        source_sha=source_sha, tag_sha=target_sha, run_url=run_url,
        run_attempt=os.environ["GITHUB_RUN_ATTEMPT"],
        assets=[dict(name=p.name, size=p.stat().st_size, sha256=digest(p)) for p in assets]),
        indent=2) + "\n", encoding="utf-8")
    # Validate every file before --clobber can replace any existing asset.
    # The explicit list excludes every other platform's assets.
    subprocess.run(["gh", "release", "upload", tag, "--repo", repository, "--clobber",
                    *(str(p) for p in assets), str(info)], check=True)
    with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as stream:
        stream.write(f"Uploaded {platform} assets to [{tag}]({url}).\n\n"
                     f"Built commit: `{source_sha}`; release tag commit: `{target_sha}`.\n\n")
        if source_sha != target_sha:
            stream.write("This recovery build includes fixes after the release tag; the tag was not moved.\n\n")
        stream.write("\n".join(f"- `{p.name}`" for p in [*assets, info]) + "\n")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def recovery_api(endpoint):
    return json.loads(output("gh", "api", f"repos/polobread/KeyKey/{endpoint}"))


def recovery_download(tag, name, directory, release):
    matches = [item for item in release["assets"] if item["name"] == name]
    require(len(matches) == 1, f"Expected one published Linux asset: {name}")
    item = matches[0]
    require(item["size"] > 0 and re.fullmatch(r"sha256:[0-9a-f]{64}", item.get("digest") or ""),
            f"Published Linux asset has no size/digest: {name}")
    subprocess.run(["gh", "release", "download", tag, "--repo", "polobread/KeyKey",
                    "--pattern", name, "--dir", str(directory)], check=True)
    path = directory / name
    require(path.is_file() and not path.is_symlink() and path.stat().st_size == item["size"]
            and "sha256:" + digest(path) == item["digest"], f"Published Linux bytes differ: {name}")
    return path


def verify_recovery_report(report, artifact, source, raw_hashes, version):
    original = report["original"]
    require(original["repository"] == "polobread/KeyKey" and original["run_id"] == artifact["run_id"]
            and original["artifact_id"] == artifact["id"] and original["artifact_name"] == artifact["name"]
            and original["source_sha"] == source and original["archive_sha256"] == artifact["sha256"]
            and original["package_files"] == raw_hashes, "Linux verification report provenance differs")
    require(original.get("product_rebuilt") is False and original.get("tag_moved") is False
            and report.get("product_rebuilt") is False and report.get("tag_moved") is False,
            "Linux recovery must preserve the original product and tag")
    lifecycle = report["lifecycle"]
    require(lifecycle["status"] == "passed" and lifecycle["version"] == f"{version}-1+ubuntu24.04"
            and lifecycle["architecture"] == "amd64", "Linux lifecycle verification did not pass")
    tests, results = report["x11"]["tests"], report["case_results"]
    require(report["x11"]["status"] == "passed" and tests and len(tests) == len(set(tests))
            and set(tests) == set(results) and all(item.get("status") == "passed" and item.get("test") == name
                for name, item in results.items()), "Linux X11 verification did not pass every reported case")
    require(report["notification_integration"] == "passed", "Linux notification verification did not pass")


def verify_cdn_bytes(url, path):
    checksum, size = hashlib.sha256(), 0
    with urlopen(url, timeout=60) as response:
        require(response.geturl().startswith("https://"), "CDN redirected to insecure transport")
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            require(size <= path.stat().st_size, "CDN asset exceeds expected size")
            checksum.update(chunk)
    require(size == path.stat().st_size and checksum.hexdigest() == digest(path), "CDN Linux bytes differ")


def mirror_existing_linux(version, directory, artifact_run, verification_sha256):
    require(os.environ.get("GITHUB_REPOSITORY") == "polobread/KeyKey"
            and os.environ.get("GITHUB_REF") == "refs/heads/master"
            and os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch",
            "Existing Linux mirror requires manual dispatch on reviewed official master")
    require(artifact_run and artifact_run > 0 and re.fullmatch(r"[0-9a-f]{64}", verification_sha256 or ""),
            "Original artifact run and approved public verification SHA-256 are required")
    tag = os.environ["RELEASE_TAG"]
    require(release_tag("workflow_dispatch", "", tag, version) and channels.parse_version(tag[1:])[1] == "stable",
            "Existing Linux recovery requires a published stable release")
    verify_release(tag, "polobread/KeyKey")
    source = tag_commit(tag)
    require(re.fullmatch(r"[0-9a-f]{40}", source), "Release tag source is invalid")
    run = recovery_api(f"actions/runs/{artifact_run}")
    require(run["id"] == artifact_run and run["repository"]["full_name"] == "polobread/KeyKey"
            and run["head_repository"]["full_name"] == "polobread/KeyKey"
            and run["path"] == ".github/workflows/linux-ci.yml" and run["event"] == "release"
            and run["head_sha"] == source and run["status"] == "completed"
            and run["conclusion"] in ("success", "cancelled"), "Original Linux release run does not match the tag")
    listing = recovery_api(f"actions/runs/{artifact_run}/artifacts?per_page=100")
    name = f"linux-ubuntu-24.04-debian-packages-{source}"
    matches = [item for item in listing["artifacts"] if item["name"] == name]
    require(listing["total_count"] <= 100 and len(matches) == 1, "Expected one original Linux package artifact")
    artifact = matches[0]
    require(not artifact["expired"] and artifact["size_in_bytes"] > 0
            and artifact["workflow_run"]["id"] == artifact_run and artifact["workflow_run"]["head_sha"] == source
            and re.fullmatch(r"sha256:[0-9a-f]{64}", artifact.get("digest") or ""),
            "Original Linux artifact is expired or has mismatched provenance")
    identity = dict(run_id=artifact_run, id=artifact["id"], name=name,
                    sha256=artifact["digest"][7:], size=artifact["size_in_bytes"])
    require(not directory.exists() or not any(directory.iterdir()), "Use an empty Linux recovery directory")
    directory.mkdir(parents=True, exist_ok=True)
    archive = directory / "original-artifact.zip"
    with archive.open("xb") as stream:
        subprocess.run(["gh", "api", f"repos/polobread/KeyKey/actions/artifacts/{artifact['id']}/zip"],
                       stdout=stream, check=True)
    require(archive.stat().st_size == identity["size"] and digest(archive) == identity["sha256"],
            "Original Linux artifact ZIP size/digest differs")
    packages = directory / "packages"
    packages.mkdir()
    with zipfile.ZipFile(archive) as bundle:
        entries = bundle.infolist()
        require(entries and len({entry.filename for entry in entries}) == len(entries)
                and all(not entry.is_dir() and entry.filename == Path(entry.filename).name
                    and "/" not in entry.filename and "\\" not in entry.filename
                    and not stat.S_ISLNK(entry.external_attr >> 16) and 0 < entry.file_size < 2**31
                    for entry in entries), "Unsafe original Linux artifact entries")
        for entry in entries:
            with bundle.open(entry) as incoming, (packages / entry.filename).open("xb") as outgoing:
                shutil.copyfileobj(incoming, outgoing)
    assets = verified_assets(packages, "linux", version)
    raw_hashes = {path.name: digest(path) for path in packages.iterdir()}
    published = recovery_api(f"releases/tags/{tag}")
    require(published["tag_name"] == tag and not published["draft"] and not published["prerelease"],
            "Published Linux release changed")
    downloaded = directory / "published"
    downloaded.mkdir()
    info_name = f"chichi77-KeyKey-{version}-linux-build-info.json"
    report_name = f"chichi77-KeyKey-{version}-linux-verification.json"
    info_path = recovery_download(tag, info_name, downloaded, published)
    report_path = recovery_download(tag, report_name, downloaded, published)
    require(digest(report_path) == verification_sha256, "Public Linux verification SHA-256 was not approved")
    info = json.loads(info_path.read_text(encoding="utf-8"))
    expected = dict(platform="linux", version=version, release_tag=tag, release_version=version,
                    update_channel="stable", source_sha=source, tag_sha=source,
                    original_artifact=identity, verification_report=dict(name=report_name, sha256=verification_sha256))
    require(all(info.get(key) == value for key, value in expected.items()) and info.get("product_rebuilt") is False
            and info.get("original_run_conclusion") == run["conclusion"]
            and info.get("run_url") == f"https://github.com/polobread/KeyKey/actions/runs/{artifact_run}",
            "Linux build info does not describe the original artifact and approved verification")
    require(info.get("assets") == [dict(name=path.name, size=path.stat().st_size, sha256=digest(path))
                                    for path in assets], "Linux build info package hashes differ")
    verify_recovery_report(json.loads(report_path.read_text(encoding="utf-8")), identity, source, raw_hashes, version)
    for path in assets:
        published_path = recovery_download(tag, path.name, downloaded, published)
        require(published_path.stat().st_size == path.stat().st_size and digest(published_path) == digest(path),
                "Published Linux package differs from the original artifact")
    mirrored = [*assets, info_path, report_path]
    bucket = os.environ["RELEASE_MIRROR_BUCKET"].strip()
    distribution = os.environ["RELEASE_MIRROR_DISTRIBUTION_ID"].strip()
    base = os.environ["RELEASE_MIRROR_BASE_URL"].rstrip("/")
    parsed = urlsplit(base)
    require(re.fullmatch(r"[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]", bucket)
            and re.fullmatch(r"[A-Z0-9]+", distribution) and parsed.scheme == "https" and parsed.hostname
            and not (parsed.username or parsed.password or parsed.path or parsed.query or parsed.fragment),
            "Invalid Linux mirror destination")
    require(tag_commit(tag) == source, "Release tag changed before Linux mirror")
    prefix = f"keykey/releases/download/{tag}"
    for path in mirrored:
        key, checksum = f"{prefix}/{path.name}", base64.b64encode(bytes.fromhex(digest(path))).decode()
        result = subprocess.run(["aws", "s3api", "put-object", "--bucket", bucket, "--key", key,
            "--body", str(path), "--if-none-match", "*", "--checksum-algorithm", "SHA256",
            "--checksum-sha256", checksum, "--content-type", mimetypes.guess_type(path.name)[0] or "application/octet-stream",
            "--cache-control", "public,max-age=0,s-maxage=31536000,must-revalidate",
            "--no-cli-pager", "--output", "json"], capture_output=True, text=True)
        require(result.returncode == 0 or "(PreconditionFailed)" in result.stderr,
                "Linux conditional S3 upload failed")
        if result.returncode == 0:
            require(json.loads(result.stdout).get("ChecksumSHA256") == checksum, "Linux S3 upload checksum differs")
        fetched = directory / (path.name + ".readback")
        subprocess.run(["aws", "s3api", "get-object", "--bucket", bucket, "--key", key,
                        "--checksum-mode", "ENABLED", str(fetched), "--no-cli-pager"], check=True)
        require(fetched.stat().st_size == path.stat().st_size and digest(fetched) == digest(path),
                "Existing Linux S3 object differs; never overwrite it")
    paths = [f"/{prefix}/{path.name}" for path in mirrored]
    invalidation = json.loads(output("aws", "cloudfront", "create-invalidation", "--distribution-id", distribution,
                                     "--paths", *paths, "--no-cli-pager", "--output", "json"))
    subprocess.run(["aws", "cloudfront", "wait", "invalidation-completed", "--distribution-id", distribution,
                    "--id", invalidation["Invalidation"]["Id"], "--no-cli-pager"], check=True)
    for path in mirrored:
        verify_cdn_bytes(f"{base}/{prefix}/{quote(path.name, safe='')}", path)
    message = "Original Linux artifact and public recovery evidence verified on GitHub, S3 and CDN. No product rebuild or tag changes."
    print(message)
    with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as stream:
        stream.write(message + "\n\n" + "\n".join(
            f"- [{path.name}]({base}/{prefix}/{quote(path.name, safe='')})" for path in mirrored) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("resolve", "publish", "mirror", "mirror-existing-linux"))
    parser.add_argument("--version", required=True)
    parser.add_argument("--platform", choices=("macos", "windows", "linux"))
    parser.add_argument("--directory", type=Path)
    parser.add_argument("--artifact-run", type=int)
    parser.add_argument("--verification-sha256")
    args = parser.parse_args()
    if args.command == "resolve":
        resolve(args.version)
    elif not args.platform or not args.directory:
        parser.error(f"{args.command} requires --platform and --directory")
    elif args.command == "publish":
        publish(args.platform, args.version, args.directory)
    elif args.command == "mirror-existing-linux":
        if args.platform != "linux":
            parser.error("mirror-existing-linux requires --platform linux")
        mirror_existing_linux(args.version, args.directory, args.artifact_run, args.verification_sha256)
    else:
        mirror(args.platform, args.version, args.directory)


if __name__ == "__main__":
    main()
