#!/usr/bin/env python3
"""Mirror reviewed RSS XML files only; never generate feeds or publish installers."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from urllib.parse import unquote, urlsplit
from urllib.request import urlopen
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "update"))
import channels

PREFIX = "keykey/update"
CHANNELS = ("stable", "beta")
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
CACHE_CONTROL = "public,max-age=0,s-maxage=60,must-revalidate"
MAX_SIZE = 1024 * 1024


def feeds(directory, update_channel="stable"):
    if update_channel not in CHANNELS:
        raise ValueError("unsupported feed channel")
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError("feed directory must be a real directory")
    result = []
    for path in sorted(directory.glob("*.xml")):
        if path.is_symlink() or not path.is_file() or not re.fullmatch(r"[a-z0-9][a-z0-9-]*\.xml", path.name):
            raise ValueError(f"unsafe feed filename: {path.name}")
        if not 0 < path.stat().st_size <= MAX_SIZE:
            raise ValueError(f"feed must be nonempty and at most 1 MiB: {path.name}")
        data = path.read_bytes()
        # Require UTF-8; reject DTD/entity declarations, including UTF-16 bypasses.
        text = data.decode("utf-8-sig")
        if re.search(r"<!\s*(DOCTYPE|ENTITY)\b", text, re.IGNORECASE):
            raise ValueError(f"DTD/entities are not allowed: {path.name}")
        root = ET.fromstring(data)
        if root.tag != "rss" or root.get("version") != "2.0" or len(root.findall("channel")) != 1:
            raise ValueError(f"expected RSS 2.0 with one channel: {path.name}")
        channel = root.find("channel")
        links = channel.findall("link")
        # The existing signed appcast generator omits the optional channel link.
        if not channel.findtext("title") or len(links) > 1:
            raise ValueError(f"feed must have a title and at most one channel link: {path.name}")
        for element in links:
            link = urlsplit(element.text or "")
            if link.scheme != "https" or not link.hostname or link.username or link.password:
                raise ValueError(f"channel link must be HTTPS without credentials: {path.name}")
        for item in channel.findall("item"):
            enclosure = item.find("enclosure")
            version = item.findtext(f"{{{SPARKLE}}}version")
            if enclosure is not None:
                version = version or enclosure.get(f"{{{SPARKLE}}}version")
            if not version or not re.fullmatch(rf"{channels.VERSION}(?:b[1-9]\d*)?", version):
                raise ValueError(f"update item requires a supported machine version: {path.name}")
            if update_channel == "stable":
                display = item.findtext(f"{{{SPARKLE}}}shortVersionString") or version
                url = enclosure.get("url", "") if enclosure is not None else item.findtext("link", "")
                if not re.fullmatch(channels.VERSION, version) or "beta" in display.lower() \
                        or re.search(r"/v[^/]*-beta", unquote(urlsplit(url).path)):
                    raise ValueError(f"beta updates cannot be published to stable: {path.name}")
        result.append((path.name, data))
    if not result:
        raise ValueError("no XML feeds to sync; remote objects are never deleted")
    return result


def snapshot(directory, update_channel):
    if update_channel == "all":
        # Validate both channels before any writes, preserving exact relative keys.
        return [(f"{channel}/{name}", data) for channel in CHANNELS
                for name, data in feeds(directory / channel, channel)]
    return [(f"{update_channel}/{name}", data) for name, data in feeds(directory, update_channel)]


def aws(*arguments):
    return json.loads(subprocess.check_output(
        ["aws", *arguments, "--no-cli-pager", "--output", "json"], text=True))


def verify_cdn(url, expected):
    for attempt in range(3):
        try:
            with urlopen(url, timeout=20) as response:
                if urlsplit(response.geturl()).scheme != "https" or response.read(MAX_SIZE + 1) != expected:
                    raise ValueError(f"CDN bytes differ from the reviewed feed: {url}")
            return
        except (OSError, ValueError):
            if attempt == 2:
                raise
            time.sleep(2 * (attempt + 1))


def sync(directory, update_channel="stable"):
    captured = snapshot(directory, update_channel)  # Validate all channels before external writes.
    bucket = os.environ["RELEASE_MIRROR_BUCKET"].strip()
    distribution = os.environ["RELEASE_MIRROR_DISTRIBUTION_ID"].strip()
    base = os.environ["RELEASE_MIRROR_BASE_URL"].strip().rstrip("/")
    parsed = urlsplit(base)
    if not re.fullmatch(r"[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]", bucket):
        raise ValueError("RELEASE_MIRROR_BUCKET must be an S3 bucket name")
    if not re.fullmatch(r"[A-Z0-9]+", distribution):
        raise ValueError("RELEASE_MIRROR_DISTRIBUTION_ID is required")
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password \
            or parsed.path or parsed.query or parsed.fragment:
        raise ValueError("RELEASE_MIRROR_BASE_URL must be an HTTPS origin")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    if not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("expected a checked-out source commit")

    paths = []
    with tempfile.TemporaryDirectory(prefix="keykey-update-feeds-") as temporary:
        for name, data in captured:
            staged = Path(temporary) / name
            staged.parent.mkdir(parents=True, exist_ok=True)
            staged.write_bytes(data)
            key = f"{PREFIX}/{name}"
            checksum = base64.b64encode(hashlib.sha256(data).digest()).decode()
            record = aws("s3api", "put-object", "--bucket", bucket, "--key", key,
                "--body", str(staged), "--content-type", "application/rss+xml; charset=utf-8",
                "--cache-control", CACHE_CONTROL, "--checksum-algorithm", "SHA256",
                "--checksum-sha256", checksum, "--metadata", f"source-sha={commit}")
            if record.get("ChecksumSHA256") != checksum:
                raise ValueError(f"S3 upload checksum mismatch: {name}")
            fetched = Path(temporary) / f"{name}.download"
            aws("s3api", "get-object", "--bucket", bucket, "--key", key,
                "--checksum-mode", "ENABLED", str(fetched))
            if fetched.read_bytes() != data:
                raise ValueError(f"S3 read-back differs from the reviewed feed: {name}")
            paths.append(f"/{key}")

    invalidation = aws("cloudfront", "create-invalidation", "--distribution-id", distribution,
        "--paths", *paths)["Invalidation"]["Id"]
    subprocess.run(["aws", "cloudfront", "wait", "invalidation-completed",
        "--distribution-id", distribution, "--id", invalidation, "--no-cli-pager"], check=True)
    for name, data in captured:
        verify_cdn(f"{base}/{PREFIX}/{name}", data)
    summary = f"Synced {len(captured)} XML feeds from master commit `{commit}`; S3 and CDN bytes verified.\n\n"
    summary += "\n".join(f"- [{name}]({base}/{PREFIX}/{name})" for name, _ in captured) + "\n"
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as stream:
            stream.write(summary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path("update"))
    parser.add_argument("--channel", choices=(*CHANNELS, "all"), default="all",
        help="all: directory contains stable/ and beta/; single channel: directory contains XML files")
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    if args.check_only:
        print(f"Validated {len(snapshot(args.directory, args.channel))} RSS XML feeds; no AWS/network writes.")
    else:
        sync(args.directory, args.channel)


if __name__ == "__main__":
    main()
