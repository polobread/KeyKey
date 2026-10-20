#!/usr/bin/env python3
"""Validate local Windows release inputs and transport signed EXE/ZIP assets. No signing secrets."""
import argparse
import hashlib
import importlib.util
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
FRONTEND = ROOT / "Source/Loaders/Windows-TSF"
RUNTIME_FILES = ("KeyKeyTsf.dll", "KeyKeySettings.exe", "KeyKeySettingsBackend.dll",
                 "KeyKeyDeployment.exe", "WinSparkle.dll", "WinSparkle-LICENSE.txt", "Databases/KeyKey.db")
FILES = tuple(f"{arch}/{name}" for arch in ("x64", "x86") for name in RUNTIME_FILES) + ("x86/KeyKeyRegistration.exe",)
CHECKS = {"updater-sdk", "settings", "deployment", "shared-x64-x86", "shared-x86-x64",
          "shared-managed-x64", "shared-managed-x86", "update-metadata", "release-transport", "signing-policy",
          *(f"{step}-{arch}" for arch in ("x64", "x86") for step in ("configure", "build", "ctest", "updater"))}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run(*args):
    result = subprocess.run(list(map(str, args)), cwd=ROOT, capture_output=True)
    require(result.returncode == 0, f"{Path(args[0]).name} operation failed; check authentication and prerequisites")
    return result.stdout.decode("utf-8-sig").strip()


def api(endpoint):
    return json.loads(run("gh", "api", f"repos/{REPOSITORY}/{endpoint}"))


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def product_version():
    text = (FRONTEND / "CMakeLists.txt").read_text(encoding="utf-8")
    match = re.search(r"project\(KeyKeyWindowsTsf VERSION (\d+\.\d+\.\d+) LANGUAGES", text)
    require(match, "Windows product version is missing")
    return match[1]


def local_source(sha):
    require(not run("git", "ls-files", "--", "keykey-update-private.pem*", "**/keykey-update-private.pem*"),
            "Windows update private key must never be tracked or staged")
    require(run("git", "rev-parse", "HEAD") == sha, "Use a checkout of the exact release tag commit")
    require(not run("git", "status", "--porcelain", "--untracked-files=normal"),
            "Release checkout must be clean (keep outputs in the ignored out directory)")
    require(run("git", "remote", "get-url", "origin") in
            (f"https://github.com/{REPOSITORY}.git", f"https://github.com/{REPOSITORY}",
             f"git@github.com:{REPOSITORY}.git"), "Origin must be the official KeyKey repository")


def validate_tag(tag):
    require(re.fullmatch(r"v\d+\.\d+\.\d+(?:-beta[1-9]\d*)?", tag), "Invalid release tag")


def remote_tag(tag):
    validate_tag(tag)
    obj = api(f"git/ref/tags/{tag}")["object"]
    for _ in range(5):
        if obj["type"] == "commit":
            return obj["sha"]
        require(obj["type"] == "tag", "Release ref is not a commit/tag")
        obj = api(f"git/tags/{obj['sha']}")["object"]
    raise ValueError("Too many annotated tag indirections")


def context(tag, remote=False, check_local=True):
    validate_tag(tag)
    version = product_version()
    release_version = channels.release_version(tag, version)
    source = remote_tag(tag) if remote else run("git", "rev-parse", f"refs/tags/{tag}^{{commit}}")
    require(re.fullmatch(r"[0-9a-f]{40}", source), "Invalid source commit")
    if check_local:
        local_source(source)
        # A release source must have reached reviewed master before it is built.
        run("git", "merge-base", "--is-ancestor", source, "origin/master")
    return dict(schema=2, platform="windows", repository=REPOSITORY, build_source="local",
                version=version, release_version=release_version, release_tag=tag, source_sha=source, tag_sha=source)


def prepare(tag, destination):
    identity = context(tag)
    require(not destination.exists(), "Release output already exists; use Sign for completed build inputs")
    destination.mkdir(parents=True)
    write_json(destination / "context.json", identity)
    print(json.dumps(identity))


def verify_checks(report, identity):
    require(report.get("schema") == 1 and report.get("source_sha") == identity["source_sha"],
            "Build check source mismatch")
    checks = report.get("checks", [])
    require(len(checks) == len(CHECKS) and {c["name"] for c in checks} == CHECKS and
            all(c.get("passed") is True for c in checks), "All local release checks must pass")


def stage(destination):
    identity = read_json(destination / "context.json")
    require(identity == context(identity["release_tag"]), "Local source/tag changed since preparing the build")
    verify_checks(read_json(destination / "build/build-checks.json"), identity)
    inputs = destination / "inputs"
    require(not inputs.exists(), "Build input snapshot already exists")
    inputs.mkdir()
    for name in FILES:
        arch, relative = name.split("/", 1)
        path = destination / "build" / arch / "Release" / relative
        require(path.is_file() and not path.is_symlink(), f"Missing local build input: {name}")
        target = inputs / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
    write_json(destination / "built-inputs.json", dict(identity, files={name: sha256(inputs / name) for name in FILES}))


def verify_built(destination):
    identity = read_json(destination / "context.json")
    require(identity == context(identity["release_tag"]), "Local source/tag changed since building")
    manifest = read_json(destination / "built-inputs.json")
    require({k: manifest.get(k) for k in identity} == identity and set(manifest["files"]) == set(FILES),
            "Local build input identity/file set mismatch")
    verify_checks(read_json(destination / "build/build-checks.json"), identity)
    for name in FILES:
        path = destination / "inputs" / name
        require(path.is_file() and not path.is_symlink() and sha256(path) == manifest["files"][name],
                f"Local build input hash mismatch: {name}")
    return identity


def asset_names(version):
    prefix = f"chichi77-KeyKey-{version}-windows"
    payloads = [f"{prefix}-x64-setup.exe", f"{prefix}-x64.zip", f"{prefix}-x86.zip"]
    return tuple(name for payload in payloads for name in (payload, payload + ".sha256")) + (f"{prefix}-build-info.json",)


def native_verify(installer, version):
    require(sys.platform == "win32", "Authenticode verification must run on Windows")
    run("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ROOT / "update/verify-windows.ps1",
        "-Installer", installer, "-ExpectedVersion", channels.parse_version(version)[0], "-SigningMode", "authenticode")


def load_package_verifier():
    spec = importlib.util.spec_from_file_location("keykey_verify_package", FRONTEND / "Packaging/verify-package.py")
    verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verifier)
    return verifier


def verify_zip(package, version, architecture, native=True, reference_installer=None):
    verifier = load_package_verifier()
    manifest = verifier.verify(package, require_signed=True)
    product_version = channels.parse_version(version)[0]
    require(manifest["Version"] == product_version and manifest["Architecture"] == architecture, "ZIP version/architecture mismatch")
    if native:
        require(sys.platform == "win32", "ZIP signatures must be verified on Windows")
        with zipfile.ZipFile(package) as archive, tempfile.TemporaryDirectory() as temp:
            names = {name.replace("\\", "/"): name for name in archive.namelist()}
            prefix = next(name.removesuffix("PackageManifest.json") for name in names if name.endswith("/PackageManifest.json"))
            for entry in manifest["Files"]:
                relative = entry["Path"].replace("\\", "/")
                if relative.lower().endswith((".exe", ".dll")):
                    target = Path(temp) / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with archive.open(names[prefix + "Payload/" + relative]) as source, target.open("xb") as output:
                        shutil.copyfileobj(source, output)
            arguments = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", FRONTEND / "Packaging/Verify-SignedPayload.ps1",
                         "-Directory", temp, "-ExpectedVersion", product_version, "-Architecture", architecture]
            if reference_installer is not None:
                arguments.extend(("-ReferenceInstaller", reference_installer))
            run(*arguments)


def record(destination):
    identity = verify_built(destination)
    directory = destination / "signed"
    names = asset_names(identity["version"])
    require(not (directory / names[-1]).exists(), "Build info already exists; signed releases are immutable")
    # Verify actual archive bytes, not a claim in the package manifest.
    native_verify(directory / names[0], identity["version"])
    for arch in ("x64", "x86"):
        verify_zip(directory / f"chichi77-KeyKey-{identity['version']}-windows-{arch}.zip", identity["version"], arch,
                   reference_installer=directory / names[0])
    assets = [dict(name=name, size=(directory / name).stat().st_size, sha256=sha256(directory / name)) for name in names[:-1]]
    report = dict(identity, windows_signing="authenticode", assets=assets,
                  checks=read_json(destination / "build/build-checks.json"),
                  input_sha256=read_json(destination / "built-inputs.json")["files"])
    write_json(directory / names[-1], report)
    verify_signed(directory, identity)


def verify_signed(directory, identity):
    names = asset_names(identity["version"])
    report = read_json(directory / names[-1])
    for key, value in identity.items():
        require(report.get(key) == value, f"Signed release provenance mismatch: {key}")
    require(report.get("windows_signing") == "authenticode", "Only signed Windows releases are accepted")
    verify_checks(report.get("checks", {}), identity)
    require(set(report.get("input_sha256", {})) == set(FILES) and
            all(re.fullmatch(r"[0-9a-f]{64}", h) for h in report["input_sha256"].values()), "Build input record mismatch")
    assets = report.get("assets", [])
    require(len(assets) == len(names) - 1 and {a["name"] for a in assets} == set(names[:-1]), "Release asset set mismatch")
    for entry in assets:
        path = directory / entry["name"]
        require(path.is_file() and not path.is_symlink() and path.stat().st_size == entry["size"] and
                sha256(path) == entry["sha256"], f"Signed asset hash mismatch: {entry['name']}")
    for name in names[:-1:2]:
        require((directory / (name + ".sha256")).read_text(encoding="ascii").strip() ==
                f"{sha256(directory / name)}  {name}", f"Signed checksum mismatch: {name}")
    return [directory / name for name in names]


def verify_native_assets(directory, version):
    names = asset_names(version)
    native_verify(directory / names[0], version)
    for arch in ("x64", "x86"):
        verify_zip(directory / f"chichi77-KeyKey-{version}-windows-{arch}.zip", version, arch, reference_installer=directory / names[0])


def release_assets(tag):
    release = api(f"releases/tags/{tag}")
    require(not release["draft"] and release["prerelease"] == (channels.parse_version(tag[1:])[1] == "beta"),
            "Publish a matching Release/Pre-release first")
    assets = []
    for page in range(1, 101):
        batch = api(f"releases/{release['id']}/assets?per_page=100&page={page}")
        assets.extend(batch)
        if len(batch) < 100:
            return {a["name"]: a for a in assets}
    raise ValueError("Unexpected release asset count")


def download_asset(tag, name, directory):
    run("gh", "release", "download", tag, "--repo", REPOSITORY, "--pattern", name, "--dir", directory)


def publish(tag, destination, approved_sha256):
    identity = context(tag, remote=True)
    require(identity == verify_built(destination), "Remote tag differs from the local build source")
    directory = destination / "signed"
    info = directory / asset_names(identity["version"])[-1]
    require(sha256(info) == approved_sha256, "Release files differ from the approved build-info SHA-256")
    paths = verify_signed(directory, identity)
    require(read_json(info)["checks"] == read_json(destination / "build/build-checks.json") and
            read_json(info)["input_sha256"] == read_json(destination / "built-inputs.json")["files"],
            "Build records changed after signing")
    verify_native_assets(directory, identity["version"])
    existing = release_assets(tag)
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
        "-f", f"release_tag={tag}", "-f", f"receipt_sha256={sha256(info)}")
    print("Seven signed release assets uploaded and read back. Check the CDN mirror workflow approval and result.")


def fetch_published(tag, receipt_digest, directory):
    require(re.fullmatch(r"[0-9a-f]{64}", receipt_digest), "Invalid receipt digest")
    identity = context(tag, remote=True, check_local=False)
    require(run("git", "rev-parse", "HEAD") == identity["source_sha"], "Mirror checkout must equal the release tag")
    require(not directory.exists(), "Mirror staging directory already exists")
    directory.mkdir(parents=True)
    assets = release_assets(tag)
    for name in asset_names(identity["version"]):
        require(name in assets, f"Signed release asset is missing: {name}")
        download_asset(tag, name, directory)
    require(sha256(directory / asset_names(identity["version"])[-1]) == receipt_digest, "Receipt digest mismatch")
    verify_signed(directory, identity)
    verify_native_assets(directory, identity["version"])


def mirror(tag, directory, receipt_digest):
    identity = context(tag, remote=True, check_local=False)
    receipt = directory / asset_names(identity["version"])[-1]
    require(sha256(receipt) == receipt_digest, "Mirror receipt digest mismatch")
    paths = verify_signed(directory, identity)
    # Windows already validated signatures; validate archive contents again on the mirror runner.
    for arch in ("x64", "x86"):
        verify_zip(directory / f"chichi77-KeyKey-{identity['version']}-windows-{arch}.zip", identity["version"], arch, native=False)
    bucket = os.environ["RELEASE_MIRROR_BUCKET"]
    distribution = os.environ["RELEASE_MIRROR_DISTRIBUTION_ID"]
    base_url = os.environ["RELEASE_MIRROR_BASE_URL"].rstrip("/")
    parsed = urlsplit(base_url)
    require(re.fullmatch(r"[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]", bucket) and
            re.fullmatch(r"[A-Z0-9]+", distribution) and parsed.scheme == "https" and parsed.hostname and
            not (parsed.username or parsed.password or parsed.path or parsed.query or parsed.fragment), "Invalid mirror configuration")
    prefix = f"keykey/releases/download/{tag}"
    for path in paths:
        key = f"{prefix}/{path.name}"
        result = subprocess.run(["aws", "s3api", "put-object", "--bucket", bucket, "--key", key,
                                 "--body", str(path), "--if-none-match", "*", "--checksum-algorithm", "SHA256",
                                 "--content-type", mimetypes.guess_type(path.name)[0] or "application/octet-stream",
                                 "--cache-control", "public,max-age=31536000,immutable"], capture_output=True)
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
    message = "Signed Windows EXE and x64/x86 ZIP assets verified on S3 and CDN. No update feeds were changed."
    print(message)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as stream:
            stream.write(message + "\n\n" + "\n".join(f"- [{p.name}]({base_url}/{prefix}/{quote(p.name, safe='')})" for p in paths) + "\n")


def verify_url(url, path):
    digest, size = hashlib.sha256(), 0
    with urlopen(url, timeout=30) as response:
        require(response.geturl().startswith("https://"), "CDN redirected to insecure transport")
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            require(size <= path.stat().st_size, "CDN response size mismatch")
            digest.update(chunk)
    require(size == path.stat().st_size and digest.hexdigest() == sha256(path), "CDN readback mismatch")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "stage", "verify-built", "record", "publish", "fetch-published", "mirror"))
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--tag", default="")
    parser.add_argument("--receipt-sha256")
    parser.add_argument("--approved-sha256")
    args = parser.parse_args()
    if args.command == "prepare":
        prepare(args.tag, args.directory)
    elif args.command == "stage":
        stage(args.directory)
    elif args.command == "verify-built":
        verify_built(args.directory)
    elif args.command == "record":
        record(args.directory)
    elif args.command == "publish":
        publish(args.tag, args.directory, args.approved_sha256)
    elif args.command == "fetch-published":
        fetch_published(args.tag, args.receipt_sha256, args.directory)
    else:
        mirror(args.tag, args.directory, args.receipt_sha256)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, AssertionError, zipfile.BadZipFile) as error:
        print(f"Windows release stopped: {error}", file=sys.stderr)
        sys.exit(1)
