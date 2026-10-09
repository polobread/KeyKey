#!/usr/bin/env python3
"""Fetch checksum-pinned updater SDKs; never run downloaded executables."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import tarfile
import tempfile
from urllib.parse import urlsplit
from urllib.request import urlopen
import zipfile

ROOT = Path(__file__).resolve().parent


def load_config():
    config = json.loads((ROOT / "config.json").read_text(encoding="utf-8"))
    if config.get("schema_version") != 1:
        raise ValueError("unsupported update configuration")
    key = config["public_ed25519_key"]
    feeds = [config[name] for name in ("macos_feed_url", "windows_x64_feed_url", "windows_x86_feed_url")]
    if key and len(base64.b64decode(key, validate=True)) != 32:
        raise ValueError("public Ed25519 key must be base64 of 32 bytes")
    if any(feeds) and not key:
        raise ValueError("update feed requires a pinned public key")
    for url in filter(None, feeds):
        parsed = urlsplit(url)
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
            raise ValueError("update feed must be an HTTPS URL without credentials or fragments")
    return config


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
        raise ValueError("run python3 Updates/prepare.py fetch macos before building")
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
    info.update(SUEnableAutomaticChecks=False, SUAllowsAutomaticUpdates=False,
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
    args = parser.parse_args()
    load_config()
    if args.command == "fetch":
        fetch(args.platform)
    else:
        embed_macos(args.app)


if __name__ == "__main__":
    main()
