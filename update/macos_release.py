#!/usr/bin/env python3
"""Prepare a verified macOS updater candidate; never publish/promote a feed."""
import argparse
from pathlib import Path
import plistlib
import re

import metadata
import prepare
import channels

REPOSITORY = Path(__file__).resolve().parent.parent
PLISTS = ("Source/Loaders/OSX-IMK/Takao-Info.plist", "Source/PreferenceApplications/OSX/Info.plist",
          "Source/Utilities/PhraseEditor/OSX/Info.plist", "Source/Distributions/Takao/Installer-OSX-Help/Info.plist")


def source_version(repository=REPOSITORY):
    versions = []
    for name in PLISTS:
        info = plistlib.loads((repository / name).read_bytes())
        versions.extend((info.get("CFBundleVersion"), info.get("CFBundleShortVersionString")))
    if len(set(versions)) != 1 or not isinstance(versions[0], str) or not re.fullmatch(r"\d+\.\d+\.\d+", versions[0]):
        raise ValueError("all four macOS bundles must declare the same x.y.z version")
    return versions[0]


def prepare_candidate(package, version, tag, source_sha, tag_sha, key, base_url, destination, openssl):
    if version != source_version():
        raise ValueError("requested update version does not match the macOS sources")
    config = prepare.load_config()
    update_version = channels.release_version(tag, version)
    channel = channels.parse_version(update_version)[1]
    if "release_version" in config and config["release_version"] != update_version:
        raise ValueError("selected build configuration does not match the requested macOS release")
    feed_field = "macos_beta_feed_url" if channel == "beta" else "macos_feed_url"
    if not config.get(feed_field):
        raise ValueError("configure and review the macOS feed before preparing a production updater candidate")
    manifest = dict(schema_version=1, channel=channel, releases=[dict(target="macos-arm64", version=update_version,
        release_tag=tag, source_sha=source_sha, tag_sha=tag_sha, file=str(package), minimum_system_version="15.0.0",
        notes="macOS 琦琦輸入法更新。安裝需要管理員確認；完成後從輸入法選單選取琦琦，並在「文字編輯」試打。")])
    return metadata.build(manifest, key, base_url, destination, config["public_ed25519_key"], openssl)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--openssl", default="openssl")
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--tag-sha", required=True)
    parser.add_argument("--key", type=Path, required=True)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    prepare_candidate(args.package, args.version, args.tag, args.source_sha, args.tag_sha,
        args.key, args.base_url, args.out, args.openssl)
    print("Verified macOS updater candidate prepared; upload immutable packages before reviewed feed promotion.")


if __name__ == "__main__":
    main()
