#!/usr/bin/env python3
"""Fetch checksum-pinned updater SDKs; never run downloaded executables."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import tarfile
import tempfile
from urllib.parse import urlsplit
from urllib.request import urlopen
import zipfile

import channels

ROOT = Path(__file__).resolve().parent


def load_config(path=None):
    config_path = Path(path or os.environ.get("KEYKEY_UPDATE_CONFIG", ROOT / "config.json"))
    config = json.loads(config_path.read_text(encoding="utf-8"))
    if config.get("schema_version") != 1:
        raise ValueError("unsupported update configuration")
    key = config["public_ed25519_key"]
    fields = ("macos_feed_url", "windows_x64_feed_url", "windows_x86_feed_url",
              "macos_beta_feed_url", "windows_x64_beta_feed_url", "windows_x86_beta_feed_url")
    feeds = [config.get(name, "") for name in fields]
    if key and len(base64.b64decode(key, validate=True)) != 32:
        raise ValueError("public Ed25519 key must be base64 of 32 bytes")
    if any(feeds) and not key:
        raise ValueError("update feed requires a pinned public key")
    for url in filter(None, feeds):
        parsed = urlsplit(url)
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
            raise ValueError("update feed must be an HTTPS URL without credentials or fragments")
    if "release_version" in config:
        _, channel, _ = channels.parse_version(config["release_version"])
        if config.get("update_channel") != channel:
            raise ValueError("release version does not match the build update channel")
        if channel == "beta" and any(config.get(f"{platform}_feed_url", "") !=
                config.get(f"{platform}_beta_feed_url", "") for platform in ("macos", "windows_x64", "windows_x86")):
            raise ValueError("beta build must use only its reviewed beta feeds")
    return config


def select_release_config(tag, version, destination):
    release_version = channels.release_version(tag, version)
    channel = channels.parse_version(release_version)[1]
    # Always start from the reviewed config, never a previously selected beta build.
    config = load_config(ROOT / "config.json")
    config.update(release_version=release_version, update_channel=channel)
    if channel == "beta":
        for platform in ("macos", "windows_x64", "windows_x86"):
            # No fallback to stable when the beta endpoint is unconfigured.
            config[f"{platform}_feed_url"] = config.get(f"{platform}_beta_feed_url", "")
    if destination.exists():
        raise ValueError("build config output must not exist")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")


def stamp_macos(app):
    config = load_config()
    version = config.get("release_version")
    if not version:
        return
    base, _, _ = channels.parse_version(version)
    info_path = app / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    if info.get("CFBundleShortVersionString") != base:
        raise ValueError("built macOS product does not match the requested release")
    info.update(CFBundleVersion=channels.native_version(version), KeyKeyReleaseVersion=version)
    info_path.write_bytes(plistlib.dumps(info))


def fetch(platform):
    lock = json.loads((ROOT / "dependencies.json").read_text())[platform]
    destination = ROOT / ".cache" / f"{platform}-{lock['version']}"
    # Reverify the archive on every prepare, not just a mutable cache marker.
    archive = ROOT / ".cache" / Path(urlsplit(lock["url"]).path).name
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.is_file():
        with tempfile.NamedTemporaryFile(dir=archive.parent, delete=False) as stream:
            temporary = Path(stream.name)
            try:
                with urlopen(lock["url"], timeout=60) as response:
                    shutil.copyfileobj(response, stream)
                stream.close()
                if hashlib.sha256(temporary.read_bytes()).hexdigest() != lock["sha256"]:
                    raise ValueError("updater SDK checksum mismatch")
                temporary.replace(archive)
            finally:
                temporary.unlink(missing_ok=True)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != lock["sha256"]:
        raise ValueError("cached updater SDK checksum mismatch; remove only this cached archive and retry")
    # Fresh extraction repairs missing/modified SDK files as well as stale caches.
    with tempfile.TemporaryDirectory(dir=archive.parent) as stage:
        if platform == "macos":
            with tarfile.open(archive) as bundle:
                bundle.extractall(stage, filter="data")
        else:
            with zipfile.ZipFile(archive) as bundle:
                for member in bundle.namelist():
                    if member.startswith(("/", "\\")) or ".." in Path(member).parts:
                        raise ValueError("unsafe SDK archive path")
                bundle.extractall(stage)
        if destination.exists():
            shutil.rmtree(destination)  # Exact version-specific tool-owned cache only.
        shutil.copytree(stage, destination, symlinks=True)
    print(destination)
    return destination


def embed_macos(app):
    config = load_config()
    sdk = ROOT / ".cache" / "macos-2.10.0"
    framework = sdk / "Sparkle.framework"
    if not framework.is_dir():
        raise ValueError("run python3 update/prepare.py fetch macos before building")
    contents = app / "Contents"
    destination = contents / "Frameworks" / "Sparkle.framework"
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(framework, destination, symlinks=True)
    notices = contents / "Resources" / "LICENSES"
    notices.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(sdk / "LICENSE", notices / "Sparkle-LICENSE.txt")
    info_path = contents / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info.update(SUEnableAutomaticChecks=False, SUAllowsAutomaticUpdates=False, SUAutomaticallyUpdate=False,
                SUSendProfileInfo=False, SUVerifyUpdateBeforeExtraction=True,
                SUScheduledCheckInterval=86400)
    for name, value in (("SUFeedURL", config["macos_feed_url"]),
                        ("SUPublicEDKey", config["public_ed25519_key"])):
        if value:
            info[name] = value
        else:
            info.pop(name, None)
    info_path.write_bytes(plistlib.dumps(info))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    fetch_parser = sub.add_parser("fetch")
    fetch_parser.add_argument("platform", choices=("macos", "windows"))
    embed = sub.add_parser("embed-macos")
    embed.add_argument("app", type=Path)
    stamp = sub.add_parser("stamp-macos")
    stamp.add_argument("app", type=Path)
    select = sub.add_parser("select-release")
    select.add_argument("--tag", default="")
    select.add_argument("--version", required=True)
    select.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    load_config()
    if args.command == "fetch":
        fetch(args.platform)
    elif args.command == "embed-macos":
        embed_macos(args.app)
    elif args.command == "stamp-macos":
        stamp_macos(args.app)
    else:
        select_release_config(args.tag, args.version, args.out)


if __name__ == "__main__":
    main()
