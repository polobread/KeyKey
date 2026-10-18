#!/usr/bin/env python3
"""Stage CI inputs and transport locally signed Windows releases; never handles signing secrets."""
import argparse
import hashlib
import json
import mimetypes
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from urllib.parse import quote, urlsplit
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "update"))
import channels

REPOSITORY = "polobread/KeyKey"
WORKFLOW = ".github/workflows/prepare-windows-signing.yml"
FRONTEND = ROOT / "Source/Loaders/Windows-TSF"
FILES = (
    "x64/KeyKeyTsf.dll", "x64/KeyKeySettings.exe", "x64/KeyKeySettingsBackend.dll",
    "x64/KeyKeyDeployment.exe", "x64/WinSparkle.dll", "x64/WinSparkle-LICENSE.txt",
    "x64/Databases/KeyKey.db", "x86/KeyKeyTsf.dll", "x86/KeyKeyRegistration.exe",
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run(*args):
    # Do not echo external commands or their diagnostics into release logs.
    result = subprocess.run(list(map(str, args)), cwd=ROOT, capture_output=True)
    require(result.returncode == 0, f"{Path(args[0]).name} operation failed; check authentication and prerequisites")
    return result.stdout.decode("utf-8-sig").strip()


def api(endpoint):
    return json.loads(run("gh", "api", f"repos/{REPOSITORY}/{endpoint}"))


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def artifact_name(version, run_id, attempt):
    return f"keykey-windows-signing-{version}-{run_id}-{attempt}"


def product_version():
    text = (FRONTEND / "CMakeLists.txt").read_text(encoding="utf-8")
    match = re.search(r"project\(KeyKeyWindowsTsf VERSION (\d+\.\d+\.\d+) LANGUAGES", text)
    require(match, "Windows product version is missing")
    return match[1]


def local_source(sha):
    require(run("git", "rev-parse", "HEAD") == sha, "Use a checkout of the exact CI source commit")
    require(not run("git", "status", "--porcelain", "--untracked-files=normal"),
            "Release checkout must be clean (keep local outputs in the ignored out directory)")
    origin = run("git", "remote", "get-url", "origin")
    require(origin in (f"https://github.com/{REPOSITORY}.git", f"https://github.com/{REPOSITORY}",
                       f"git@github.com:{REPOSITORY}.git"), "Origin must be the official KeyKey repository")


def remote_tag(tag):
    require(re.fullmatch(r"v\d+\.\d+\.\d+(?:-beta[1-9]\d*)?", tag), "Invalid release tag")
    obj = api(f"git/ref/tags/{tag}")["object"]
    for _ in range(5):
        if obj["type"] == "commit":
            return obj["sha"]
        require(obj["type"] == "tag", "Release ref is not a commit/tag")
        obj = api(f"git/tags/{obj['sha']}")["object"]
    raise ValueError("Too many annotated tag indirections")


def provenance(run_id, tag, check_local=True):
    require(str(run_id).isdigit() and int(run_id) > 0, "Invalid run ID")
    record = api(f"actions/runs/{run_id}")
    require(record["status"] == "completed" and record["conclusion"] == "success", "CI run must have succeeded")
    require(record["event"] in ("release", "workflow_dispatch"), "Untrusted CI event")
    require(record["repository"]["full_name"].lower() == REPOSITORY.lower()
            and record["head_repository"]["full_name"].lower() == REPOSITORY.lower(), "Fork CI runs are not accepted")
    require(api(f"actions/workflows/{record['workflow_id']}")["path"] == WORKFLOW, "Unexpected build workflow")
    source = record["head_sha"]
    require(re.fullmatch(r"[0-9a-f]{40}", source), "Invalid source commit")
    require(source == remote_tag(tag), "CI source must equal the current release tag commit")
    version = product_version()
    channels.release_version(tag, version)
    if check_local:
        local_source(source)
    attempt = record["run_attempt"]
    name = artifact_name(version, run_id, attempt)
    artifacts = api(f"actions/runs/{run_id}/artifacts?per_page=100")
    require(artifacts["total_count"] <= 100, "Unexpected artifact count")
    matches = [a for a in artifacts["artifacts"] if a["name"] == name]
    require(len(matches) == 1, "Expected one signing artifact for this run attempt")
    artifact = matches[0]
    require(artifact["workflow_run"]["head_sha"] == source, "Artifact source mismatch")
    require(re.fullmatch(r"sha256:[0-9a-f]{64}", artifact.get("digest") or ""), "Artifact SHA-256 is unavailable")
    return dict(schema=1, repository=REPOSITORY, workflow=WORKFLOW, version=version,
                release_tag=tag, source_sha=source, tag_sha=source, run_id=int(run_id),
                run_attempt=attempt, artifact_id=artifact["id"], artifact_digest=artifact["digest"])


def stage(destination, x64, x86, tag):
    require(not destination.exists(), "Signing artifact output already exists")
    version = product_version()
    channels.release_version(tag, version)
    source = run("git", "rev-parse", "HEAD")
    if tag:
        require(source == os.environ["RELEASE_TAG_SHA"], "CI tag/source mismatch")
    require(os.environ["GITHUB_REPOSITORY"] == REPOSITORY, "Only the official repository may stage release inputs")
    destination.mkdir(parents=True)
    for name in FILES:
        architecture, relative = name.split("/", 1)
        base = x64 if architecture == "x64" else x86
        cache = base / "CMakeCache.txt"
        if cache.is_file() and re.search(r"(?m)^CMAKE_CONFIGURATION_TYPES:", cache.read_text(encoding="utf-8")):
            base = base / "Release"
        path = base / relative
        require(path.is_file() and not path.is_symlink(), f"Missing build input: {name}")
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
    manifest = dict(schema=1, repository=REPOSITORY, workflow=WORKFLOW, version=version,
                    source_sha=source, release_tag=tag,
                    run_id=int(os.environ["GITHUB_RUN_ID"]), run_attempt=int(os.environ["GITHUB_RUN_ATTEMPT"]),
                    files={name: sha256(destination / name) for name in FILES})
    write_json(destination / "signing-inputs.json", manifest)


def verify_bundle(directory, context):
    manifest = json.loads((directory / "signing-inputs.json").read_text(encoding="utf-8"))
    for key in ("schema", "repository", "workflow", "version", "source_sha", "release_tag", "run_id", "run_attempt"):
        require(manifest.get(key) == context[key], f"Signing input provenance mismatch: {key}")
    require(set(manifest["files"]) == set(FILES), "Signing input file set mismatch")
    for name in FILES:
        path = directory / name
        require(path.is_file() and not path.is_symlink() and sha256(path) == manifest["files"][name],
                f"Signing input hash mismatch: {name}")
    return manifest


def extract(archive, directory):
    # No paths supplied by an archive are ever used as extraction destinations.
    with zipfile.ZipFile(archive) as bundle:
        names = [i.filename for i in bundle.infolist() if not i.is_dir()]
        expected = {*FILES, "signing-inputs.json"}
        require(len(names) == len(expected) and set(names) == expected, "Unexpected/duplicate archive entries")
        require(sum(i.file_size for i in bundle.infolist()) < 1024**3, "Signing archive is too large")
        for name in sorted(expected):
            target = directory / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with bundle.open(name) as source, target.open("xb") as output:
                shutil.copyfileobj(source, output)


def download(run_id, tag, destination):
    context = provenance(run_id, tag)
    if destination.exists():
        saved = json.loads((destination / "context.json").read_text(encoding="utf-8"))
        require(saved == context, "Cached CI identity changed; use a new run")
        require("sha256:" + sha256(destination / "inputs.zip") == context["artifact_digest"], "Cached artifact digest mismatch")
        with tempfile.TemporaryDirectory() as temp:
            extract(destination / "inputs.zip", Path(temp))
            manifest = verify_bundle(Path(temp), context)
        require(verify_bundle(destination / "inputs", context) == manifest, "Cached input manifest mismatch")
        print(json.dumps(context))
        return
    destination.mkdir(parents=True)
    archive = destination / "inputs.zip"
    with archive.open("xb") as output:
        result = subprocess.run(["gh", "api", f"repos/{REPOSITORY}/actions/artifacts/{context['artifact_id']}/zip"],
                                cwd=ROOT, stdout=output, stderr=subprocess.PIPE)
    require(result.returncode == 0, "Artifact download failed")
    require("sha256:" + sha256(archive) == context["artifact_digest"], "Downloaded artifact digest mismatch")
    extract(archive, destination / "inputs")
    verify_bundle(destination / "inputs", context)
    write_json(destination / "context.json", context)
    print(json.dumps(context))


def asset_names(version):
    installer = f"chichi77-KeyKey-{version}-windows-x64-setup.exe"
    return installer, installer + ".sha256", f"chichi77-KeyKey-{version}-windows-signed-build-info.json"


def native_verify(installer, version):
    require(sys.platform == "win32", "Authenticode verification must run on Windows")
    run("powershell.exe", "-NoProfile", "-File", ROOT / "update/verify-windows.ps1",
        "-Installer", installer, "-ExpectedVersion", version, "-SigningMode", "authenticode")


def record(destination):
    context = json.loads((destination / "context.json").read_text(encoding="utf-8"))
    verify_bundle(destination / "inputs", context)
    installer, checksum, info = asset_names(context["version"])
    package = destination / "signed" / installer
    native_verify(package, context["version"])
    report = dict(context, windows_signing="authenticode", installer=installer, sha256=sha256(package))
    write_json(destination / "signed" / info, report)


def verify_signed(directory, context):
    installer, checksum, info = asset_names(context["version"])
    report = json.loads((directory / info).read_text(encoding="utf-8"))
    for key, value in context.items():
        require(report.get(key) == value, f"Signed release provenance mismatch: {key}")
    require(report.get("windows_signing") == "authenticode" and report.get("installer") == installer,
            "Signed release identity mismatch")
    digest = sha256(directory / installer)
    require(report["sha256"] == digest, "Signed installer hash mismatch")
    require((directory / checksum).read_text(encoding="ascii").strip() == f"{digest}  {installer}",
            "Signed checksum mismatch")
    return [directory / name for name in (installer, checksum, info)]


def release_assets(tag):
    release = api(f"releases/tags/{tag}")
    require(not release["draft"] and release["prerelease"] == (channels.parse_version(tag[1:])[1] == "beta"),
            "Publish a matching Release/Pre-release first")
    # Follow pagination explicitly; never mistake an omitted asset for an absent one.
    assets = []
    for page in range(1, 101):
        batch = api(f"releases/{release['id']}/assets?per_page=100&page={page}")
        assets.extend(batch)
        if len(batch) < 100:
            return {a["name"]: a for a in assets}
    raise ValueError("Unexpected release asset count")


def download_asset(tag, name, directory):
    run("gh", "release", "download", tag, "--repo", REPOSITORY, "--pattern", name, "--dir", directory)


def publish(run_id, tag, destination, approved_sha256):
    context = provenance(run_id, tag)
    saved = json.loads((destination / "context.json").read_text(encoding="utf-8"))
    require(saved == context, "CI artifact/run changed since signing")
    require("sha256:" + sha256(destination / "inputs.zip") == context["artifact_digest"], "Cached artifact digest mismatch")
    # Re-extract authenticated bytes, rather than trusting mutable local input metadata.
    with tempfile.TemporaryDirectory() as temp:
        extract(destination / "inputs.zip", Path(temp))
        verify_bundle(Path(temp), context)
    paths = verify_signed(destination / "signed", context)
    require(sha256(paths[0]) == approved_sha256, "Installer bytes differ from the approved SHA-256")
    native_verify(paths[0], context["version"])
    existing = release_assets(tag)
    # Preflight every collision before uploading anything. Identical retries are safe.
    with tempfile.TemporaryDirectory() as temp:
        for path in paths:
            if path.name in existing:
                download_asset(tag, path.name, temp)
                require(sha256(Path(temp) / path.name) == sha256(path), "Existing release asset has different bytes; refusing overwrite")
    for path in paths:
        if path.name not in existing:
            run("gh", "release", "upload", tag, "--repo", REPOSITORY, path)
    for path in paths:
        with tempfile.TemporaryDirectory() as temp:
            download_asset(tag, path.name, temp)
            require(sha256(Path(temp) / path.name) == sha256(path), "Published asset readback mismatch")
    run("gh", "workflow", "run", "mirror-windows-signed.yml", "--repo", REPOSITORY, "--ref", "master",
        "-f", f"release_tag={tag}", "-f", f"build_run_id={run_id}", "-f", f"receipt_sha256={sha256(paths[2])}")
    print("Signed assets uploaded and read back. Mirror workflow requested; check its release environment approval and result.")


def fetch_published(run_id, tag, receipt_digest, directory):
    require(re.fullmatch(r"[0-9a-f]{64}", receipt_digest), "Invalid receipt digest")
    context = provenance(run_id, tag)
    require(not directory.exists(), "Mirror staging directory already exists")
    directory.mkdir(parents=True)
    assets = release_assets(tag)
    for name in asset_names(context["version"]):
        require(name in assets, "Signed release asset is missing")
        download_asset(tag, name, directory)
    require(sha256(directory / asset_names(context["version"])[2]) == receipt_digest, "Receipt digest mismatch")
    paths = verify_signed(directory, context)
    native_verify(paths[0], context["version"])


def mirror(tag, directory, receipt_digest):
    version = product_version()
    channels.release_version(tag, version)
    receipt = directory / asset_names(version)[2]
    require(sha256(receipt) == receipt_digest, "Mirror receipt digest mismatch")
    context = json.loads(receipt.read_text(encoding="utf-8"))
    require(context == dict(provenance(context["run_id"], tag), windows_signing="authenticode",
                            installer=asset_names(version)[0], sha256=context["sha256"]), "Mirror provenance mismatch")
    paths = verify_signed(directory, {k: v for k, v in context.items() if k not in ("windows_signing", "installer", "sha256")})
    bucket = os.environ["RELEASE_MIRROR_BUCKET"]
    distribution = os.environ["RELEASE_MIRROR_DISTRIBUTION_ID"]
    base_url = os.environ["RELEASE_MIRROR_BASE_URL"].rstrip("/")
    parsed = urlsplit(base_url)
    require(re.fullmatch(r"[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]", bucket)
            and re.fullmatch(r"[A-Z0-9]+", distribution) and parsed.scheme == "https" and parsed.hostname
            and not (parsed.username or parsed.password or parsed.path or parsed.query or parsed.fragment),
            "Invalid mirror configuration")
    prefix = f"keykey/releases/download/{tag}"
    for path in paths:
        key = f"{prefix}/{path.name}"
        result = subprocess.run(["aws", "s3api", "put-object", "--bucket", bucket, "--key", key,
                                 "--body", str(path), "--if-none-match", "*", "--checksum-algorithm", "SHA256",
                                 "--content-type", mimetypes.guess_type(path.name)[0] or "application/octet-stream",
                                 "--cache-control", "public,max-age=31536000,immutable"], capture_output=True)
        # A collision may be an identical retry. Read back even after a failed put;
        # no replacement write is ever attempted.
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / path.name
            run("aws", "s3api", "get-object", "--bucket", bucket, "--key", key, target)
            require(sha256(target) == sha256(path), "Mirror collision/readback mismatch; refusing overwrite")
        if result.returncode != 0:
            require(b"PreconditionFailed" in result.stderr or b"412" in result.stderr, "Mirror upload failed")
    invalidation = json.loads(run("aws", "cloudfront", "create-invalidation", "--distribution-id", distribution,
        "--paths", *(f"/{prefix}/{p.name}" for p in paths), "--no-cli-pager", "--output", "json"))
    run("aws", "cloudfront", "wait", "invalidation-completed", "--distribution-id", distribution,
        "--id", invalidation["Invalidation"]["Id"], "--no-cli-pager")
    for path in paths:
        verify_url(f"{base_url}/{prefix}/{quote(path.name, safe='')}", path)
    message = "Signed Windows assets verified on S3 and CDN. No update feeds were changed."
    print(message)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as stream:
            stream.write(message + "\n\n" + "\n".join(
                f"- [{p.name}]({base_url}/{prefix}/{quote(p.name, safe='')})" for p in paths) + "\n")


def verify_url(url, path):
    digest = hashlib.sha256()
    size = 0
    with urlopen(url, timeout=30) as response:
        require(response.geturl().startswith("https://"), "CDN redirected to insecure transport")
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            require(size <= path.stat().st_size, "CDN response size mismatch")
            digest.update(chunk)
    require(size == path.stat().st_size and digest.hexdigest() == sha256(path), "CDN readback mismatch")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("stage", "download", "record", "publish", "fetch-published", "mirror"))
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--x64", type=Path)
    parser.add_argument("--x86", type=Path)
    parser.add_argument("--run-id")
    parser.add_argument("--tag", default="")
    parser.add_argument("--receipt-sha256")
    parser.add_argument("--approved-sha256")
    args = parser.parse_args()
    if args.command == "stage":
        stage(args.directory, args.x64, args.x86, args.tag)
    elif args.command == "download":
        download(args.run_id, args.tag, args.directory)
    elif args.command == "record":
        record(args.directory)
    elif args.command == "publish":
        publish(args.run_id, args.tag, args.directory, args.approved_sha256)
    elif args.command == "fetch-published":
        fetch_published(args.run_id, args.tag, args.receipt_sha256, args.directory)
    else:
        mirror(args.tag, args.directory, args.receipt_sha256)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, zipfile.BadZipFile) as error:
        print(f"Windows release stopped: {error}", file=sys.stderr)
        sys.exit(1)
