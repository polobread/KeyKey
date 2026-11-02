#!/usr/bin/env python3
"""Prepare checksummed Cargo sources in a staged Unix source/package tree.

Use this only on the staged crate: the working repository's Cargo policy is not
changed. The resulting tree builds with --locked --offline and no registry cache.
"""
import argparse
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-dir", type=Path, required=True)
    parser.add_argument("--cargo", default=os.environ.get("CARGO", "cargo"))
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    core = args.core_dir.resolve()
    if not (core / "Cargo.lock").is_file():
        parser.error("staged core must contain Cargo.lock")
    command = [args.cargo, "vendor", "--locked", "--versioned-dirs"]
    if args.offline or os.environ.get("KEYKEY_GUANYINMA_OFFLINE") in ("1", "ON"):
        command.append("--offline")
    command.append("vendor")
    config = subprocess.check_output(command, cwd=core, text=True)
    destination = core / ".cargo/config.toml"
    if destination.exists():
        parser.error("refusing to replace an existing staged Cargo configuration")
    destination.parent.mkdir(exist_ok=True)
    destination.write_text(config)


if __name__ == "__main__":
    main()
