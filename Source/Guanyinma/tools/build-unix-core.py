#!/usr/bin/env python3
"""Build the locked Unix static core with the frontend's system SQLite provider.

This is a build/link helper, not a core-test runner. It never cooks a database.
Python 3.10 is supported for the Ubuntu 22.04 build environment.
"""
import argparse
import os
from pathlib import Path
import re
import shutil
import shlex
import subprocess
import sys
import tempfile


CORE = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--cargo", default=os.environ.get("CARGO", "cargo"))
    parser.add_argument("--sqlite-include", type=Path, required=True)
    parser.add_argument("--sqlite-library", type=Path, required=True)
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    cargo = shutil.which(args.cargo)
    if cargo is None:
        parser.error("cargo is unavailable; install the pinned rust-toolchain.toml toolchain or set CARGO")
    match = re.search(r'^channel\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"\s*$',
                      (CORE / "rust-toolchain.toml").read_text(), re.MULTILINE)
    if match is None:
        parser.error("rust-toolchain.toml must pin a complete stable version")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    sqlite_include = args.sqlite_include.resolve()
    # Preserve the development-link directory even when libsqlite3.so points
    # at a runtime object in another directory without a -lsqlite3 alias.
    sqlite_library = args.sqlite_library.absolute()
    if not (sqlite_include / "sqlite3.h").is_file() or not sqlite_library.is_file():
        parser.error("the CMake-selected system SQLite development headers/library are missing")
    env = os.environ.copy()
    env.update(RUSTUP_TOOLCHAIN=match.group(1), SQLITE3_INCLUDE_DIR=str(sqlite_include),
               SQLITE3_LIB_DIR=str(sqlite_library.parent), SQLITE3_STATIC="0",
               SQLITE3_NO_PKG_CONFIG="1")
    version = subprocess.check_output([cargo, "--version"], env=env, text=True, cwd=CORE)
    if not version.startswith("cargo " + match.group(1) + " "):
        parser.error("cargo must use the exact pinned Rust toolchain: " + match.group(1))
    # The archive is linked into Fcitx's shared addon, not only executables.
    env["RUSTFLAGS"] = (env.get("RUSTFLAGS", "") + " -C relocation-model=pic").strip()
    command = [cargo, "rustc", "--lib", "--release", "--locked", "--no-default-features",
               "--target-dir", str(output / "target")]
    if args.offline or env.get("KEYKEY_GUANYINMA_OFFLINE") in ("1", "ON"):
        command.append("--offline")
    command.extend(["--", "--print", "native-static-libs"])
    completed = subprocess.run(command, cwd=CORE, env=env, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    sys.stdout.write(completed.stdout)
    sys.stderr.write(completed.stderr)
    completed.check_returncode()
    native = re.findall(r"native-static-libs:\s*([^\r\n]+)", completed.stdout + completed.stderr)
    if not native:
        raise RuntimeError("Rust did not report the static core's native link libraries")
    # A linker response file preserves target-specific libraries and order,
    # including FreeBSD's native dependencies, rather than guessing Linux flags.
    # SQLite is linked by CMake's exact SQLite::SQLite3 target, which may live
    # outside default linker search paths. Do not replace it with -lsqlite3.
    flags = [flag for flag in shlex.split(native[-1]) if flag != "-lsqlite3"]
    native_libraries = " ".join(shlex.quote(flag) for flag in flags) + "\n"
    response = output / "native-static-libs.rsp"
    if not response.is_file() or response.read_text() != native_libraries:
        response.write_text(native_libraries)
    archive = output / "target/release/libguanyinma.a"
    destination = output / "libguanyinma.a"
    if not destination.is_file() or archive.read_bytes() != destination.read_bytes():
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(dir=output, prefix="libguanyinma.", delete=False) as file:
                temporary = Path(file.name)
                with archive.open("rb") as source:
                    shutil.copyfileobj(source, file)
            temporary.replace(destination)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
