#!/usr/bin/env python3
"""Build a pinned GNOME Shell 46 Kimpanel extension with the monitor fixes."""

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path


ORIGINAL_HASHES = {
    "extension.js": "5887f37967cc227f1c937ef67ac538603bdf5f2cc8a51a35c507cbb116f20ca6",
    "panel.js": "fef4dc8852d7719aecb14c9496d2daccc81286054d172974f80005c30bd9dfba",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="unmodified official v83 extension")
    parser.add_argument("output", type=Path, help="new directory for the patched copy")
    args = parser.parse_args()
    source = args.source.resolve()
    output = args.output.resolve()
    if not source.is_dir() or output.exists() or output.is_relative_to(source):
        raise RuntimeError("Source must exist; output must be new and outside source")
    metadata = json.loads((source / "metadata.json").read_text())
    if metadata.get("uuid") != "kimpanel@kde.org" or metadata.get("version") != 83:
        raise RuntimeError("Expected official kimpanel@kde.org version 83")
    for name, expected in ORIGINAL_HASHES.items():
        if (source / name).is_symlink():
            raise RuntimeError(f"Source {name} must be a regular file")
        actual = hashlib.sha256((source / name).read_bytes()).hexdigest()
        if actual != expected:
            raise RuntimeError(f"Unrecognized {name} SHA-256: {actual}")
    patch = Path(__file__).with_name("kimpanel-v83.patch")
    shutil.copytree(source, output, symlinks=True)
    try:
        subprocess.run(["patch", "--batch", "-p1", "-i", str(patch)],
                       cwd=output, check=True, capture_output=True, text=True)
    except (OSError, subprocess.CalledProcessError):
        shutil.rmtree(output)
        raise
    print(output)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, json.JSONDecodeError,
            subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
