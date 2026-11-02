#!/usr/bin/env python3
"""Prepare a true host-JVM JNI library with bundled SQLite; no emulator or UI."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tomllib

CORE = Path(__file__).resolve().parents[1]
SOURCE = CORE.parent / "Loaders/Android-IME/app/src/main/cpp/guanyinma_jni.cpp"

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--java-home", type=Path, default=os.environ.get("JAVA_HOME"))
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    if not args.java_home:
        parser.error("--java-home or JAVA_HOME must name a JDK with JNI headers")
    java = args.java_home.resolve()
    system = "darwin" if sys.platform == "darwin" else "win32" if sys.platform == "win32" else "linux"
    for header in (java / "include/jni.h", java / "include" / system / "jni_md.h"):
        if not header.is_file():
            raise RuntimeError("JDK JNI header is missing: " + str(header))
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment["RUSTUP_TOOLCHAIN"] = tomllib.loads((CORE / "rust-toolchain.toml").read_text())["toolchain"]["channel"]
    for key in ("SQLITE3_LIB_DIR", "SQLITE3_INCLUDE_DIR", "SQLITE3_STATIC", "SQLITE3_NO_PKG_CONFIG"):
        environment.pop(key, None)
    command = [os.environ.get("CARGO", "cargo"), "build", "--lib", "--release", "--locked",
               "--no-default-features", "--features", "bundled-sqlite", "--target-dir", str(output / "target")]
    if args.offline or os.environ.get("KEYKEY_GUANYINMA_OFFLINE") == "1":
        command += ["--offline"]
    subprocess.run(command, cwd=CORE, env=environment, check=True)
    includes = [str(java / "include"), str(java / "include" / system), str(CORE / "include")]
    if sys.platform == "win32":
        archive = output / "target/release/guanyinma.lib"
        library = output / "keykey_guanyinma.dll"
        compile_command = ["cl", "/nologo", "/std:c++17", "/utf-8", "/EHsc", "/W4", "/WX", "/MD", "/LD",
                           *["/I" + path for path in includes], str(SOURCE), str(archive),
                           "/Fo" + str(output / "guanyinma_jni.obj"), "/Fe" + str(library),
                           "ws2_32.lib", "userenv.lib", "bcrypt.lib", "ntdll.lib", "advapi32.lib", "/link", "/INCREMENTAL:NO"]
    else:
        archive = output / "target/release/libguanyinma.a"
        library = output / ("libkeykey_guanyinma.dylib" if sys.platform == "darwin" else "libkeykey_guanyinma.so")
        compiler = (["xcrun", "--sdk", "macosx", "clang++"] if sys.platform == "darwin" else [os.environ.get("CXX", "c++")])
        compile_command = compiler + ["-std=c++17", "-Wall", "-Wextra", "-Werror", "-fPIC", "-fvisibility=hidden",
                                      *["-I" + path for path in includes], str(SOURCE), str(archive), "-o", str(library)]
        if sys.platform == "darwin":
            exports = output / "jni-exports.txt"
            exports.write_text("\n".join("_Java_tw_chichi77_keykey_android_GuanyinmaNative_" + name
                                         for name in ("nativeOpen", "nativeRead", "nativeClose")) + "\n")
            compile_command += ["-dynamiclib", "-liconv", "-framework", "Security", "-framework", "CoreFoundation",
                                "-Xlinker", "-exported_symbols_list", "-Xlinker", str(exports)]
        else:
            compile_command += ["-shared", "-pthread", "-ldl", "-lm", "-Wl,--exclude-libs,ALL"]
    subprocess.run(compile_command, cwd=output, env=environment, check=True)
    print(library, flush=True)

if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print("Guanyinma host JNI build failed:", error, file=sys.stderr)
        raise SystemExit(1)
