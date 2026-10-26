#!/usr/bin/env python3
"""Build the Windows frontend's static core and shared bundled SQLite provider.

Both native cores use the exact SQLite header/library locked by Cargo.lock.
This avoids mixing WinSQLite's x86 stdcall ABI with SQLite's cdecl bindings.
The model is never generated or modified.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tomllib


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cargo", default="cargo")
    parser.add_argument("--target", choices=["x86_64-pc-windows-msvc", "i686-pc-windows-msvc"], required=True)
    parser.add_argument("--target-dir", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    version = tomllib.loads((root / "rust-toolchain.toml").read_text())["toolchain"]["channel"]
    environment = os.environ.copy()
    environment.update(CARGO_TARGET_DIR=str(args.target_dir.resolve()),
                       RUSTFLAGS="-C target-feature=+crt-static")
    # Do not inherit a caller's system SQLite override into this bundled build.
    environment.pop("LIBSQLITE3_SYS_USE_PKG_CONFIG", None)
    subprocess.run([args.cargo, f"+{version}", "build", "--locked", "--release", "--lib",
                    "--features", "bundled-sqlite", "--target", args.target], cwd=root, env=environment, check=True)
    metadata = json.loads(subprocess.check_output(
        [args.cargo, f"+{version}", "metadata", "--locked", "--format-version", "1"], cwd=root, env=environment))
    package = next(package for package in metadata["packages"] if package["name"] == "libsqlite3-sys")
    include = args.target_dir.resolve() / "include"
    include.mkdir(parents=True, exist_ok=True)
    header = Path(package["manifest_path"]).parent / "sqlite3/sqlite3.h"
    output = include / "guanyinma_sqlite3.h"
    if not output.is_file() or output.read_bytes() != header.read_bytes():
        shutil.copyfile(header, output)
    subprocess.run([sys.executable, str(root / "tools/package-runtime-notices.py"), "--platform", "windows",
                    "--cargo", args.cargo, "--output", str(args.target_dir.resolve() / "Guanyinma-NOTICES.txt")],
                   cwd=root, env=environment, check=True)


if __name__ == "__main__":
    main()
