#!/usr/bin/env python3
"""Resolve a published release and replace only one platform's verified assets."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


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
    if tag and tag != f"v{version}":
        raise ValueError(f"Release tag must be v{version}, received {tag!r}")
    return tag


def verify_release(tag, repository):
    release = json.loads(output("gh", "release", "view", tag, "--repo", repository,
                                "--json", "tagName,isDraft,url"))
    if release["tagName"] != tag or release["isDraft"]:
        raise ValueError("publish the matching GitHub Release before uploading assets")
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
    values = dict(release_tag=tag, publish_release=str(bool(tag)).lower(),
                  source_sha=source_sha, tag_sha=target_sha)
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
    assets = verified_assets(directory, platform, version)
    info = directory / f"chichi77-KeyKey-{version}-{platform}-build-info.json"
    run_url = f"{os.environ['GITHUB_SERVER_URL']}/{repository}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
    info.write_text(json.dumps(dict(platform=platform, version=version, release_tag=tag,
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("resolve", "publish"))
    parser.add_argument("--version", required=True)
    parser.add_argument("--platform", choices=("macos", "windows", "linux"))
    parser.add_argument("--directory", type=Path)
    args = parser.parse_args()
    if args.command == "resolve":
        resolve(args.version)
    elif not args.platform or not args.directory:
        parser.error("publish requires --platform and --directory")
    else:
        publish(args.platform, args.version, args.directory)


if __name__ == "__main__":
    main()
