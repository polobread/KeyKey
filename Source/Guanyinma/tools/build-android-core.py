#!/usr/bin/env python3
"""Build per-ABI Rust static archives for the Android JNI transport; no tests/UI."""
import argparse
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tomllib

CORE = Path(__file__).resolve().parents[1]
TARGETS = {
    "arm64-v8a": ("aarch64-linux-android", "aarch64-linux-android"),
    "armeabi-v7a": ("armv7-linux-androideabi", "armv7a-linux-androideabi"),
    "x86_64": ("x86_64-linux-android", "x86_64-linux-android"),
    "x86": ("i686-linux-android", "i686-linux-android"),
}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ndk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--api", type=int, default=26)
    parser.add_argument("--abis", default=",".join(TARGETS))
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    if args.api < 26:
        parser.error("KeyKey Android native builds require API 26 or later")
    host = "darwin-x86_64" if sys.platform == "darwin" else "windows-x86_64" if sys.platform == "win32" else "linux-x86_64"
    toolchain = args.ndk.resolve() / "toolchains/llvm/prebuilt" / host
    suffix = ".exe" if sys.platform == "win32" else ""
    clang = toolchain / "bin" / ("clang" + suffix)
    archiver = toolchain / "bin" / ("llvm-ar" + suffix)
    if not clang.is_file() or not archiver.is_file():
        raise RuntimeError("The configured Android NDK toolchain is missing: " + str(toolchain))
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment["RUSTUP_TOOLCHAIN"] = tomllib.loads((CORE / "rust-toolchain.toml").read_text())["toolchain"]["channel"]
    # This core owns bundled SQLite. Never inherit desktop/system provider paths.
    for key in ("SQLITE3_LIB_DIR", "SQLITE3_INCLUDE_DIR", "SQLITE3_STATIC", "SQLITE3_NO_PKG_CONFIG"):
        environment.pop(key, None)
    cargo = os.environ.get("CARGO", "cargo")
    for abi in args.abis.split(","):
        if abi not in TARGETS:
            raise ValueError("Unsupported Android ABI: " + abi)
        target, clang_target = TARGETS[abi]
        linker = toolchain / "bin" / (clang_target + str(args.api) + "-clang" + (".cmd" if sys.platform == "win32" else ""))
        if not linker.is_file():
            raise RuntimeError("The API-specific NDK linker is missing: " + str(linker))
        local = environment.copy()
        local["CARGO_TARGET_" + target.upper().replace("-", "_") + "_LINKER"] = str(linker)
        local["CC_" + target.replace("-", "_")] = str(clang)
        local["AR_" + target.replace("-", "_")] = str(archiver)
        # A single target flag contains no shell-sensitive SDK paths. cc-rs uses
        # clang's adjacent NDK sysroot automatically; rustc uses the API wrapper.
        local["CFLAGS_" + target.replace("-", "_")] = "--target=" + clang_target + str(args.api)
        command = [cargo, "build", "--lib", "--release", "--locked", "--no-default-features",
                   "--features", "bundled-sqlite", "--target", target, "--target-dir", str(output / "target")]
        if args.offline or os.environ.get("KEYKEY_GUANYINMA_OFFLINE") == "1":
            command += ["--offline"]
        subprocess.run(command, cwd=CORE, env=local, check=True)
        destination = output / abi
        destination.mkdir(exist_ok=True)
        source = output / "target" / target / "release/libguanyinma.a"
        archive = destination / "libguanyinma.a"
        if not archive.is_file() or source.read_bytes() != archive.read_bytes():
            staged = destination / "libguanyinma.a.tmp"
            shutil.copyfile(source, staged)
            staged.replace(archive)
        print("Guanyinma Android archive:", archive, flush=True)

if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print("Guanyinma Android build failed:", error, file=sys.stderr)
        raise SystemExit(1)
