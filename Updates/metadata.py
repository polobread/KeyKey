#!/usr/bin/env python3
"""Create immutable signed desktop updates and platform-specific appcasts offline.

No upload, key generation, or feed promotion occurs in this tool. Private keys
must be external PEM Ed25519 keys. OpenSSL 3 is required, not macOS LibreSSL.
"""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET
import zipfile

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
PUBLIC_DER_PREFIX = bytes.fromhex("302a300506032b6570032100")
ET.register_namespace("sparkle", SPARKLE)
TARGETS = {"macos-arm64", "windows-x64", "windows-x86"}


def public_key(key, openssl):
    encoded = subprocess.check_output([openssl, "pkey", "-in", str(key), "-pubout", "-outform", "DER"])
    if len(encoded) != 44 or not encoded.startswith(PUBLIC_DER_PREFIX):
        raise ValueError("signing key must be Ed25519")
    return base64.b64encode(encoded[12:]).decode("ascii")


def sign(path, key, openssl):
    signature = subprocess.check_output([openssl, "pkeyutl", "-sign", "-rawin", "-inkey", str(key), "-in", str(path)])
    if len(signature) != 64:
        raise ValueError("unexpected Ed25519 signature size")
    return base64.b64encode(signature).decode("ascii")


def verify(path, signature, key, openssl):
    public = base64.b64decode(key, validate=True)
    raw_signature = base64.b64decode(signature, validate=True)
    if len(public) != 32 or len(raw_signature) != 64:
        raise ValueError("invalid Ed25519 key or signature size")
    with tempfile.TemporaryDirectory() as directory:
        public_path = Path(directory) / "public.der"
        signature_path = Path(directory) / "signature.bin"
        public_path.write_bytes(PUBLIC_DER_PREFIX + public)
        signature_path.write_bytes(raw_signature)
        result = subprocess.run([openssl, "pkeyutl", "-verify", "-rawin", "-pubin", "-keyform", "DER",
            "-inkey", str(public_path), "-sigfile", str(signature_path), "-in", str(path)],
            capture_output=True, text=True)
        if result.returncode:
            raise ValueError("Ed25519 signature verification failed")


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def validate_manifest(manifest):
    if manifest.get("schema_version") != 1 or manifest.get("channel") != "stable":
        raise ValueError("only schema 1 stable releases are supported")
    entries = manifest.get("releases", [])
    if not entries:
        raise ValueError("at least one desktop release is required")
    targets = set()
    for entry in entries:
        target = entry["target"]
        if target not in TARGETS or target in targets:
            raise ValueError("unsupported or duplicate update target")
        targets.add(target)
        version = entry["version"]
        if not re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)", version):
            raise ValueError("version must be x.y.z")
        if entry["release_tag"] != f"v{version}" or not re.fullmatch(r"[a-f0-9]{40}", entry["source_sha"]):
            raise ValueError("release tag/version or source commit mismatch")
        # A stable release cannot silently ship a recovery build from a different commit.
        if entry["source_sha"] != entry["tag_sha"]:
            raise ValueError("automatic update must be built from the release tag commit")
        path = Path(entry["file"])
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError("update package is missing or empty")
        if target == "macos-arm64":
            if not path.name.endswith(".pkg.zip"):
                raise ValueError("macOS update must be a pkg.zip")
        elif path.suffix.lower() != ".exe" or "unsigned" in path.name.lower():
            raise ValueError("Windows update requires a signed setup.exe, not a ZIP/unsigned installer")
        if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", entry["minimum_system_version"]):
            raise ValueError("minimum system version is required")
        if not isinstance(entry.get("notes", ""), str):
            raise ValueError("release notes must be plain text")
    return entries


def verify_platform_package(entry):
    path = Path(entry["file"]).resolve()
    if entry["target"].startswith("windows-"):
        if sys.platform != "win32":
            raise ValueError("verify and sign Windows update metadata on Windows after Authenticode signing")
        subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-File",
            str(Path(__file__).with_name("verify-windows.ps1")), "-Installer", str(path),
            "-ExpectedVersion", entry["version"]], check=True)
    else:
        if sys.platform != "darwin":
            raise ValueError("verify macOS package notarization on macOS")
        with tempfile.TemporaryDirectory() as directory, zipfile.ZipFile(path) as archive:
            packages = [p for p in archive.namelist() if "/" not in p and p.endswith(".pkg")]
            if len(packages) != 1:
                raise ValueError("macOS archive must contain exactly one root flat package")
            # Only extract the root package, never arbitrary ZIP paths.
            package = Path(directory) / packages[0]
            with archive.open(packages[0]) as source, package.open("wb") as destination:
                shutil.copyfileobj(source, destination)
            subprocess.run(["spctl", "--assess", "--type", "install", "--verbose=2", str(package)], check=True)
            subprocess.run(["xcrun", "stapler", "validate", str(package)], check=True)
            expanded = Path(directory) / "expanded"
            subprocess.run(["pkgutil", "--expand", str(package), str(expanded)], check=True)
            versions = [ET.parse(info).getroot().attrib.get("version") for info in expanded.rglob("PackageInfo")]
            if not versions or any(version != entry["version"] for version in versions):
                raise ValueError("macOS package version does not match update metadata")


def appcast(entry):
    rss = ET.Element("rss", version="2.0")
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "琦琦輸入法更新"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"琦琦輸入法 {entry['version']}"
    ET.SubElement(item, f"{{{SPARKLE}}}version").text = entry["version"]
    ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = entry["version"]
    ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = entry["minimum_system_version"]
    # Plain text, XML-escaped notes, not a remote page that can change after signing.
    ET.SubElement(item, "description").text = "<p>" + html.escape(entry.get("notes", "")) + "</p><p>安裝後請登出再登入。</p>"
    attributes = {"url": entry["url"], "length": str(entry["size"]),
        "type": "application/octet-stream", f"{{{SPARKLE}}}edSignature": entry["ed25519_signature"]}
    if entry["target"] == "macos-arm64":
        attributes[f"{{{SPARKLE}}}installationType"] = "package"
        ET.SubElement(item, f"{{{SPARKLE}}}hardwareRequirements").text = "arm64"
    else:
        attributes[f"{{{SPARKLE}}}os"] = entry["target"]
    ET.SubElement(item, "enclosure", attributes)
    return ET.tostring(rss, encoding="utf-8", xml_declaration=True) + b"\n"


def attest(manifest, key, destination, pinned_key, openssl):
    entries = validate_manifest(manifest)
    if not pinned_key or public_key(key, openssl) != pinned_key:
        raise ValueError("private key does not match the reviewed public key")
    checksums = [digest(Path(entry["file"])) for entry in entries]
    for entry in entries:
        verify_platform_package(entry)
    if destination.exists():
        raise ValueError("attestation output directory must not exist")
    destination.mkdir(parents=True)
    for entry, checksum in zip(entries, checksums):
        package = Path(entry["file"])
        if digest(package) != checksum:
            raise ValueError("package changed during platform verification")
        record = dict(schema_version=1, release={k: v for k, v in entry.items() if k != "file"},
            sha256=checksum, size=package.stat().st_size)
        path = destination / f"{entry['target']}.attestation.json"
        path.write_text(json.dumps(record, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
        path.with_suffix(".json.sig").write_text(sign(path, key, openssl) + "\n", encoding="ascii")


def verify_attestation(entry, directory, pinned_key, openssl):
    path = directory / f"{entry['target']}.attestation.json"
    verify(path, path.with_suffix(".json.sig").read_text().strip(), pinned_key, openssl)
    record = json.loads(path.read_text(encoding="utf-8"))
    package = Path(entry["file"])
    if record.get("schema_version") != 1 or record.get("release") != {k: v for k, v in entry.items() if k != "file"} \
        or record.get("sha256") != digest(package) or record.get("size") != package.stat().st_size:
        raise ValueError("signed platform attestation does not match the package/release")


def build(manifest, key, base_url, destination, pinned_key, openssl, attestations=None):
    entries = validate_manifest(manifest)
    parsed = urlsplit(base_url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.query or parsed.fragment or parsed.username or parsed.password:
        raise ValueError("asset base URL must be HTTPS without query/credentials/fragments")
    if not pinned_key or public_key(key, openssl) != pinned_key:
        raise ValueError("private key does not match the reviewed public key in Updates/config.json")
    # Verify every package before producing any signed output.
    checksums = [digest(Path(entry["file"])) for entry in entries]
    for entry in entries:
        if attestations is None:
            verify_platform_package(entry)
        else:
            verify_attestation(entry, attestations, pinned_key, openssl)
    if destination.exists():
        raise ValueError("output directory must not exist; do not overwrite a previously signed update")
    destination.mkdir(parents=True)
    packages = destination / "packages"
    packages.mkdir()
    releases = []
    for entry, checksum in zip(entries, checksums):
        source = Path(entry["file"])
        if digest(source) != checksum:
            raise ValueError("package changed during platform verification")
        suffix = ".pkg.zip" if entry["target"] == "macos-arm64" else ".exe"
        name = f"KeyKey-{entry['version']}-{entry['target']}-{checksum}{suffix}"
        package = packages / name
        shutil.copyfile(source, package)
        if digest(package) != checksum:
            raise ValueError("package changed while staging")
        signature = sign(package, key, openssl)
        verify(package, signature, pinned_key, openssl)
        release = {k: v for k, v in entry.items() if k != "file"}
        release.update(url=f"{base_url.rstrip('/')}/{entry['release_tag']}/{name}",
            name=name, size=package.stat().st_size, sha256=checksum, ed25519_signature=signature)
        releases.append(release)
        (destination / f"{entry['target']}.xml").write_bytes(appcast(release))
    metadata = dict(schema_version=1, channel="stable", generated_at=datetime.now(timezone.utc).isoformat(),
        releases=releases, package_managers={"linux": "distribution repository", "freebsd": "ports/pkg"})
    metadata_path = destination / "metadata.json"
    metadata_path.write_text(json.dumps(metadata, sort_keys=True, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    signature = sign(metadata_path, key, openssl)
    verify(metadata_path, signature, pinned_key, openssl)
    (destination / "metadata.json.sig").write_text(signature + "\n", encoding="ascii")
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--openssl", default="openssl")
    commands = parser.add_subparsers(dest="command", required=True)
    pub = commands.add_parser("public-key")
    pub.add_argument("--key", type=Path, required=True)
    generate = commands.add_parser("build")
    generate.add_argument("--manifest", type=Path, required=True)
    generate.add_argument("--key", type=Path, required=True)
    generate.add_argument("--base-url", required=True)
    generate.add_argument("--out", type=Path, required=True)
    generate.add_argument("--attestations", type=Path,
        help="combine signed OS-verification attestations from macOS and Windows jobs")
    attestation = commands.add_parser("attest")
    attestation.add_argument("--manifest", type=Path, required=True)
    attestation.add_argument("--key", type=Path, required=True)
    attestation.add_argument("--out", type=Path, required=True)
    check = commands.add_parser("verify")
    check.add_argument("--file", type=Path, required=True)
    check.add_argument("--signature", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "public-key":
        print(public_key(args.key, args.openssl))
        return
    config = json.loads(Path(__file__).with_name("config.json").read_text())
    pinned = config["public_ed25519_key"]
    if args.command == "verify":
        verify(args.file, args.signature.read_text().strip(), pinned, args.openssl)
        print("Ed25519 signature verified")
    elif args.command == "attest":
        attest(json.loads(args.manifest.read_text(encoding="utf-8")), args.key, args.out, pinned, args.openssl)
    else:
        build(json.loads(args.manifest.read_text(encoding="utf-8")), args.key,
            args.base_url, args.out, pinned, args.openssl, args.attestations)


if __name__ == "__main__":
    main()
