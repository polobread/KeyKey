#!/usr/bin/env python3
"""Verify an existing beta EXE on Windows; no signing, execution, or publication."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "update"))
import channels
import metadata

REPOSITORY = "polobread/KeyKey"


def verify(config, destination):
    if sys.platform != "win32":
        raise ValueError("Installer verification must run on native Windows")
    tag = config["release_tag"]
    version, channel, _ = channels.parse_version(tag.removeprefix("v"))
    if not tag.startswith("v") or channel != "beta":
        raise ValueError("Only a numbered beta release is accepted")
    sha = config["source_sha"]
    if not re.fullmatch(r"[a-f0-9]{40}", sha):
        raise ValueError("Invalid source commit")
    mode = config["windows_signing"]
    if mode not in ("authenticode", "unsigned-transition"):
        raise ValueError("Invalid signing policy")
    release = json.loads(subprocess.check_output(["gh", "release", "view", tag, "--repo", REPOSITORY,
        "--json", "tagName,isDraft,isPrerelease,assets"], text=True))
    if release["tagName"] != tag or release["isDraft"] or not release["isPrerelease"]:
        raise ValueError("Expected a published GitHub Pre-release")
    prefix = f"chichi77-KeyKey-{version}"
    installer_name = prefix + "-windows-x64-setup" + (".unsigned" if mode == "unsigned-transition" else "") + ".exe"
    info_name = prefix + "-windows-build-info.json"
    with tempfile.TemporaryDirectory(prefix="keykey-beta-windows-") as scratch:
        directory = Path(scratch)
        for name in (installer_name, installer_name + ".sha256", info_name):
            subprocess.run(["gh", "release", "download", tag, "--repo", REPOSITORY,
                            "--pattern", name, "--dir", str(directory)], check=True)
        installer = directory / installer_name
        checksum = hashlib.sha256(installer.read_bytes()).hexdigest()
        expected_line = f"{checksum}  {installer_name}"
        if (directory / (installer_name + ".sha256")).read_text(encoding="utf-8-sig").strip() != expected_line:
            raise ValueError("Published checksum mismatch")
        info = json.loads((directory / info_name).read_text())
        if info.get("platform") != "windows" or info.get("version") != version \
                or info.get("release_tag") != tag or info.get("source_sha") != sha or info.get("tag_sha") != sha:
            raise ValueError("Windows build source/tag mismatch")
        records = [entry for entry in info["assets"] if entry["name"] == installer_name]
        assets = [entry for entry in release["assets"] if entry["name"] == installer_name]
        if len(records) != 1 or len(assets) != 1 or records[0]["sha256"] != checksum \
                or records[0]["size"] != installer.stat().st_size or assets[0]["size"] != installer.stat().st_size \
                or assets[0]["digest"] != "sha256:" + checksum:
            raise ValueError("Release asset/build-info mismatch")
        entry = dict(target="windows-x64", version=tag[1:], release_tag=tag, source_sha=sha, tag_sha=sha,
                     file=str(installer), minimum_system_version="10.0.0", windows_signing=mode,
                     notes="Windows beta 測試版。此版本尚無發行者簽章，安裝可能顯示未知發行者或 SmartScreen 提示。")
        metadata.verify_platform_package(entry)
        record = dict(schema_version=1, release={key: value for key, value in entry.items() if key != "file"},
                      sha256=checksum, size=installer.stat().st_size,
                      verifier_source_sha=subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
                      verifier_run_id=os.environ["GITHUB_RUN_ID"],
                      verification="native-windows-signing-state-and-product-version")
        destination.mkdir(parents=True, exist_ok=True)
        (destination / "windows-x64.verified.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
        print(f"Verified {tag}: {installer_name}, SHA-256 {checksum}, policy {mode}; installer not executed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", type=Path, default=ROOT / "update/beta/release.json")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    verify(json.loads(args.release.read_text()), args.out)
