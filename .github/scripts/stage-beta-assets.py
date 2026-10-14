#!/usr/bin/env python3
"""Add SHA-256 copies to an existing beta release; never replace assets or feeds."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.parse import urlsplit
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "update"))
import channels
import metadata

REPO = "polobread/KeyKey"


def gh(*args):
    return json.loads(subprocess.check_output(["gh", *args], text=True))


def release(config):
    tag = config["release_tag"]
    version, channel, _ = channels.parse_version(tag.removeprefix("v"))
    if tag != "v" + tag.removeprefix("v") or channel != "beta":
        raise ValueError("Only numbered beta tags may be staged")
    sha = config["source_sha"]
    if not re.fullmatch(r"[a-f0-9]{40}", sha):
        raise ValueError("Invalid release source commit")
    record = gh("release", "view", tag, "--repo", REPO,
                "--json", "tagName,isDraft,isPrerelease,assets")
    if record["tagName"] != tag or record["isDraft"] or not record["isPrerelease"]:
        raise ValueError("Expected an existing published Pre-release")
    if gh("api", f"repos/{REPO}/commits/{tag}")["sha"] != sha:
        raise ValueError("Release tag no longer matches the reviewed source")
    return version, record


def native_report(path, config, checksum, size):
    report = json.loads(path.read_text(encoding="utf-8"))
    entry = report["release"]
    expected = dict(target="windows-x64", version=config["release_tag"][1:],
                    release_tag=config["release_tag"], source_sha=config["source_sha"],
                    tag_sha=config["source_sha"], windows_signing=config["windows_signing"],
                    minimum_system_version="10.0.0")
    if report.get("schema_version") != 1 or any(entry.get(k) != v for k, v in expected.items()) \
            or report.get("sha256") != checksum or report.get("size") != size \
            or report.get("verification") != "native-windows-signing-state-and-product-version" \
            or report.get("verifier_run_id") != os.environ["GITHUB_RUN_ID"] \
            or report.get("verifier_source_sha") != subprocess.check_output(
                ["git", "rev-parse", "HEAD"], text=True).strip():
        raise ValueError("Native Windows report does not match this run/revision/package")


def packages(config, directory, record, version):
    result = []
    for platform, target, suffix in (("macos", "macos-arm64", ".pkg.zip"),
                                      ("windows", "windows-x64", ".exe")):
        original = f"chichi77-KeyKey-{version}-macos-arm64.pkg.zip" if platform == "macos" else \
            f"chichi77-KeyKey-{version}-windows-x64-setup" + \
            (".unsigned" if config["windows_signing"] == "unsigned-transition" else "") + ".exe"
        path = directory / original
        checksum = metadata.digest(path)
        size = path.stat().st_size
        info = json.loads((directory / f"chichi77-KeyKey-{version}-{platform}-build-info.json").read_text())
        if info.get("platform") != platform or info.get("version") != version \
                or info.get("release_tag") != config["release_tag"] \
                or info.get("source_sha") != config["source_sha"] or info.get("tag_sha") != config["source_sha"]:
            raise ValueError("Published build-info source/tag mismatch")
        builds = [a for a in info["assets"] if a["name"] == original]
        assets = [a for a in record["assets"] if a["name"] == original]
        if len(builds) != 1 or len(assets) != 1 or builds[0]["size"] != size \
                or builds[0]["sha256"] != checksum or assets[0]["size"] != size \
                or assets[0]["digest"] != "sha256:" + checksum or size == 0 \
                or (directory / (original + ".sha256")).read_text(encoding="utf-8-sig").strip() != f"{checksum}  {original}":
            raise ValueError("Original release package/checksum/build-info mismatch")
        name = f"KeyKey-{config['release_tag'][1:]}-{target}-{checksum}{suffix}"
        result.append(dict(target=target, original=original, name=name, sha256=checksum, size=size))
    return result


def prepare(config, directory, report):
    version, record = release(config)
    if config["windows_signing"] not in ("authenticode", "unsigned-transition"):
        raise ValueError("Unsupported Windows signing policy")
    if directory.exists():
        raise ValueError("Staging directory must not exist")
    directory.mkdir(parents=True)
    names = [f"chichi77-KeyKey-{version}-macos-arm64.pkg.zip",
             f"chichi77-KeyKey-{version}-windows-x64-setup" +
             (".unsigned" if config["windows_signing"] == "unsigned-transition" else "") + ".exe"]
    for name in names + [n + ".sha256" for n in names] + \
            [f"chichi77-KeyKey-{version}-{p}-build-info.json" for p in ("macos", "windows")]:
        subprocess.run(["gh", "release", "download", config["release_tag"], "--repo", REPO,
                        "--pattern", name, "--dir", str(directory)], check=True)
    entries = packages(config, directory, record, version)
    native_report(report, config, entries[1]["sha256"], entries[1]["size"])
    metadata.verify_platform_package(dict(target="macos-arm64", version=config["release_tag"][1:],
                                         file=str(directory / names[0])))
    for entry in entries:
        shutil.copyfile(directory / entry["original"], directory / entry["name"])
    (directory / "copies.json").write_text(json.dumps(entries, indent=2) + "\n", encoding="utf-8")
    print("Prepared byte-identical SHA-256 copies; no publication, signing or feed changes.")


def verify_download(url, checksum, size):
    import hashlib
    value = hashlib.sha256()
    count = 0
    with urlopen(url, timeout=60) as response:
        if urlsplit(response.geturl()).scheme != "https":
            raise ValueError("Download redirected away from HTTPS")
        for chunk in iter(lambda: response.read(1024 * 1024), b""):
            count += len(chunk)
            if count > size:
                raise ValueError("Downloaded copy is larger than the verified package")
            value.update(chunk)
    if count != size or value.hexdigest() != checksum:
        raise ValueError("Downloaded copy checksum/size mismatch")


def publish(config, directory, report):
    # No credentials/writes are needed to prepare. Publication requires reviewed master.
    if os.environ.get("GITHUB_REF") != "refs/heads/master" \
            or os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch" \
            or os.environ.get("GITHUB_REPOSITORY", "").lower() != REPO.lower():
        raise ValueError("Publication requires manual dispatch on reviewed master")
    version, record = release(config)
    entries = packages(config, directory, record, version)
    native_report(report, config, entries[1]["sha256"], entries[1]["size"])
    if json.loads((directory / "copies.json").read_text()) != entries:
        raise ValueError("Staging plan changed")
    for entry in entries:
        path = directory / entry["name"]
        if path.is_symlink() or metadata.digest(path) != entry["sha256"] or path.stat().st_size != entry["size"]:
            raise ValueError("Staged copy changed")
        existing = [a for a in record["assets"] if a["name"] == entry["name"]]
        if existing and (len(existing) != 1 or existing[0]["digest"] != "sha256:" + entry["sha256"]
                         or existing[0]["size"] != entry["size"]):
            raise ValueError("Existing GitHub copy differs; never overwrite it")
    bucket = os.environ["RELEASE_MIRROR_BUCKET"].strip()
    base = os.environ["RELEASE_MIRROR_BASE_URL"].strip().rstrip("/")
    distribution = os.environ["RELEASE_MIRROR_DISTRIBUTION_ID"].strip()
    parsed = urlsplit(base)
    if not re.fullmatch(r"[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]", bucket) \
            or not re.fullmatch(r"[A-Z0-9]+", distribution) or parsed.scheme != "https" \
            or not parsed.hostname or parsed.username or parsed.password or parsed.path or parsed.query or parsed.fragment:
        raise ValueError("Invalid CDN destination")
    paths = []
    for entry in entries:
        path = directory / entry["name"]
        if not any(a["name"] == entry["name"] for a in record["assets"]):
            # No --clobber, no release creation/edit, no tag or Latest changes.
            subprocess.run(["gh", "release", "upload", config["release_tag"], "--repo", REPO, str(path)], check=True)
        github_url = f"https://github.com/{REPO}/releases/download/{config['release_tag']}/{entry['name']}"
        verify_download(github_url, entry["sha256"], entry["size"])
        key = f"keykey/releases/download/{config['release_tag']}/{entry['name']}"
        checksum = base64.b64encode(bytes.fromhex(entry["sha256"])).decode()
        result = subprocess.run(["aws", "s3api", "put-object", "--bucket", bucket, "--key", key,
            "--body", str(path), "--if-none-match", "*", "--checksum-algorithm", "SHA256",
            "--checksum-sha256", checksum, "--content-type", "application/octet-stream",
            "--cache-control", "public,max-age=0,s-maxage=31536000,must-revalidate",
            "--no-cli-pager", "--output", "json"], capture_output=True, text=True)
        if result.returncode:
            # 403 is NOT absence. Only an explicit conditional conflict allows read-back.
            if "(PreconditionFailed)" not in result.stderr:
                raise subprocess.CalledProcessError(result.returncode, result.args, stderr=result.stderr)
        elif json.loads(result.stdout).get("ChecksumSHA256") != checksum:
            raise ValueError("S3 upload checksum mismatch")
        fetched = directory / (entry["name"] + ".readback")
        subprocess.run(["aws", "s3api", "get-object", "--bucket", bucket, "--key", key,
                        "--checksum-mode", "ENABLED", str(fetched), "--no-cli-pager"], check=True)
        if metadata.digest(fetched) != entry["sha256"] or fetched.stat().st_size != entry["size"]:
            raise ValueError("S3 copy differs; never overwrite it")
        paths.append("/" + key)
    invalidation = json.loads(subprocess.check_output(["aws", "cloudfront", "create-invalidation",
        "--distribution-id", distribution, "--paths", *paths, "--no-cli-pager", "--output", "json"], text=True))
    subprocess.run(["aws", "cloudfront", "wait", "invalidation-completed", "--distribution-id", distribution,
                    "--id", invalidation["Invalidation"]["Id"], "--no-cli-pager"], check=True)
    for entry, path in zip(entries, paths):
        verify_download(base + path, entry["sha256"], entry["size"])
    message = "SHA-256 copies verified on GitHub and CDN. Original assets, tags, Latest and feeds unchanged.\n"
    print(message)
    with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as stream:
        stream.write(message + "\n" + "\n".join(f"- [{e['name']}]({base}{p})" for e, p in zip(entries, paths)) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "publish"))
    parser.add_argument("--release", type=Path, default=ROOT / "update/beta/release.json")
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.release.read_text(encoding="utf-8"))
    (prepare if args.command == "prepare" else publish)(config, args.directory, args.report)
