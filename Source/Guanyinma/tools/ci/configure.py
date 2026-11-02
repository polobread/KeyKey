#!/usr/bin/env python3
"""Resolve core CI toolchains/providers and provision only owned headless devices.

This is CI infrastructure, not frontend logic. Simulator creation/boot is used
only by the iOS CI job; no Simulator.app, input method or desktop UI is opened.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tomllib
import uuid

ROOT = Path(__file__).resolve().parents[4]
CORE = ROOT / "Source/Guanyinma"
RUNNER = Path(__file__).with_name("run-target.py")
OUTPUT_VALUES = {}


def execute(argv, *, check=True):
    return subprocess.run(argv, check=check, capture_output=True, text=True)


def output(name, value):
    text = str(value)
    if "\n" in text or "\r" in text:
        raise ValueError("GitHub output must be a single line")
    OUTPUT_VALUES[name] = text
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as stream:
            stream.write(name + "=" + text + "\n")
    print(name + "=" + text)


def environment(name, value):
    text = str(value)
    if "\n" in text or "\r" in text:
        raise ValueError("GitHub environment value must be a single line")
    os.environ[name] = text
    if os.environ.get("GITHUB_ENV"):
        with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as stream:
            stream.write(name + "=" + text + "\n")
    print(name + "=" + text)


def sqlite_sdk(prefix):
    environment("SQLITE3_LIB_DIR", prefix / "lib")
    environment("SQLITE3_INCLUDE_DIR", prefix / "include")
    environment("SQLITE3_STATIC", "0")
    environment("SQLITE3_NO_PKG_CONFIG", "1")


def ios_target():
    return "aarch64-apple-ios-sim" if platform.machine().lower() in ("arm64", "aarch64") else "x86_64-apple-ios"


def native(args):
    if sys.platform == "win32":
        resolved = shutil.which("cl.exe") or shutil.which("cl")
        if not resolved:
            raise RuntimeError("MSVC cl.exe is required; initialize the Visual Studio developer environment")
        cl = Path(resolved).resolve(strict=True)
        linker = cl.with_name("link.exe")
        if not linker.is_file():
            raise RuntimeError("The MSVC linker must be adjacent to cl.exe: " + str(linker))
        # Git Bash places Git's unrelated link.exe ahead of the MSVC tools.
        # Resolve through the selected compiler instead of another PATH lookup.
        environment("CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER", linker)
        environment("CC", cl)
        # cl.exe also launches a linker for the real C consumer in this process.
        os.environ["PATH"] = str(cl.parent) + os.pathsep + os.environ.get("PATH", "")
        compiler = [str(cl)]
        if args.sqlite_provider == "system":
            prefix = Path(os.environ["VCPKG_INSTALLATION_ROOT"]) / "installed/x64-windows"
            for file in (prefix / "include/sqlite3.h", prefix / "lib/sqlite3.lib", prefix / "bin/sqlite3.dll"):
                if not file.is_file():
                    raise RuntimeError("vcpkg system SQLite dependency is missing: " + str(file))
            sqlite_sdk(prefix)
            # GITHUB_PATH affects later steps; this process starts tests now.
            os.environ["PATH"] = str(prefix / "bin") + os.pathsep + os.environ.get("PATH", "")
            if os.environ.get("GITHUB_PATH"):
                with open(os.environ["GITHUB_PATH"], "a", encoding="utf-8") as stream:
                    stream.write(str(prefix / "bin") + "\n")
    elif sys.platform == "darwin":
        compiler = ["xcrun", "--sdk", "macosx", "clang"]
        if args.sqlite_provider == "system":
            sdk = Path(execute(["xcrun", "--sdk", "macosx", "--show-sdk-path"]).stdout.strip())
            sqlite_sdk(sdk / "usr")
    else:
        compiler = ["cc"]
        if sys.platform.startswith("freebsd") and args.sqlite_provider == "system":
            sqlite_sdk(Path("/usr/local"))
    output("cc_json", json.dumps(compiler))


def configure_ios(args):
    if sys.platform != "darwin":
        raise RuntimeError("iOS simulator execution requires a macOS CI host")
    sdk = Path(execute(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"]).stdout.strip())
    clang = execute(["xcrun", "--sdk", "iphonesimulator", "--find", "clang"]).stdout.strip()
    archiver = execute(["xcrun", "--sdk", "iphonesimulator", "--find", "ar"]).stdout.strip()
    runtimes = json.loads(execute(["xcrun", "simctl", "list", "runtimes", "--json"]).stdout)["runtimes"]
    runtimes = [row for row in runtimes if row.get("isAvailable") and ".SimRuntime.iOS-" in row["identifier"]]
    if not runtimes:
        raise RuntimeError("No available iOS simulator runtime; execution is required, not a cross-build pass")
    version = lambda row: tuple(int(part) for part in row["version"].split("."))
    runtime = max(runtimes, key=version)
    parts = (list(version(runtime)) + [0, 0])[:3]
    encoded_version = parts[0] * 65536 + parts[1] * 256 + parts[2]
    device_types = json.loads(execute(["xcrun", "simctl", "list", "devicetypes", "--json"]).stdout)["devicetypes"]
    device_types = [row for row in device_types if row.get("productFamily") == "iPhone" and
                    row.get("minRuntimeVersion", 0) <= encoded_version <= row.get("maxRuntimeVersion", 4294967295)]
    if not device_types:
        raise RuntimeError("No iPhone device type supports the selected simulator runtime")
    device_type = max(device_types, key=lambda row: (row.get("minRuntimeVersion", 0), row["identifier"]))
    name = "Guanyinma-core-" + uuid.uuid4().hex
    device = execute(["xcrun", "simctl", "create", name, device_type["identifier"], runtime["identifier"]]).stdout.strip()
    uuid.UUID(device)
    args.metadata.parent.mkdir(parents=True, exist_ok=True)
    args.metadata.write_text(json.dumps(dict(device=device, name=name, runtime=runtime["identifier"],
                                            device_type=device_type["identifier"]), indent=2) + "\n")
    execute(["xcrun", "simctl", "boot", device])
    execute(["xcrun", "simctl", "bootstatus", device, "-b"])
    target = ios_target()
    c_arch = "arm64" if target.startswith("aarch64") else "x86_64"
    c_target = c_arch + "-apple-ios15.0-simulator"
    flags = ["-target", c_target, "-isysroot", str(sdk)]
    environment("SDKROOT", sdk)
    environment("IPHONEOS_DEPLOYMENT_TARGET", "15.0")
    environment("CARGO_TARGET_" + target.upper().replace("-", "_") + "_LINKER", clang)
    environment("CC_" + target.replace("-", "_"), clang)
    environment("CFLAGS_" + target.replace("-", "_"), shlex.join(flags))
    environment("AR_" + target.replace("-", "_"), archiver)
    if args.sqlite_provider == "system":
        sqlite_sdk(sdk / "usr")
    output("target", target)
    output("device", device)
    output("cc_json", json.dumps([clang, *flags]))
    output("runner_json", json.dumps([sys.executable, str(RUNNER), "ios", "--device", device]))


def configure_android(args):
    sdk = Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ["ANDROID_HOME"])
    ndk = sdk / "ndk" / args.ndk
    toolchain = ndk / "toolchains/llvm/prebuilt/linux-x86_64"
    clang = toolchain / "bin/clang"
    target = "x86_64-linux-android"
    linker = toolchain / "bin" / (target + args.api + "-clang")
    archiver = toolchain / "bin/llvm-ar"
    for executable in (clang, linker, archiver):
        if not executable.is_file():
            raise RuntimeError("Required pinned NDK tool is missing: " + str(executable))
    flags = ["--target=" + target + args.api, "--sysroot=" + str(toolchain / "sysroot")]
    environment("CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER", linker)
    environment("CC_x86_64_linux_android", clang)
    environment("CFLAGS_x86_64_linux_android", shlex.join(flags))
    environment("AR_x86_64_linux_android", archiver)
    output("target", target)
    output("cc_json", json.dumps([str(clang), *flags]))
    output("runner_json", json.dumps([sys.executable, str(RUNNER), "android", "--adb", str(sdk / "platform-tools/adb"),
                                      "--serial", args.serial, "--remote-root", args.remote_root]))


def cleanup_ios(args):
    if not args.metadata.is_file():
        print("No owned simulator was created")
        return
    record = json.loads(args.metadata.read_text())
    uuid.UUID(record["device"])
    if not record["name"].startswith("Guanyinma-core-"):
        raise ValueError("Refusing cleanup of a simulator not created by this core CI helper")
    execute(["xcrun", "simctl", "shutdown", record["device"]], check=False)
    execute(["xcrun", "simctl", "delete", record["device"]])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    toolchain_parser = sub.add_parser("toolchain")
    toolchain_parser.add_argument("--platform", default="native")
    sub.add_parser("ios-target")
    host = sub.add_parser("native")
    host.add_argument("--sqlite-provider", choices=("system", "bundled"), required=True)
    ios = sub.add_parser("ios")
    ios.add_argument("--sqlite-provider", choices=("system", "bundled"), required=True)
    ios.add_argument("--metadata", type=Path, required=True)
    cleanup = sub.add_parser("cleanup-ios")
    cleanup.add_argument("--metadata", type=Path, required=True)
    android = sub.add_parser("android")
    android.add_argument("--ndk", required=True)
    android.add_argument("--api", default="26")
    android.add_argument("--serial", default="emulator-5554")
    android.add_argument("--remote-root", required=True)
    args = parser.parse_args()
    if args.command == "toolchain":
        toolchain = tomllib.loads((CORE / "rust-toolchain.toml").read_text())["toolchain"]
        output("version", toolchain["channel"])
        output("components", ",".join(toolchain.get("components", [])))
        output("target", ios_target() if args.platform == "ios" else
               "x86_64-linux-android" if args.platform == "android" else "")
    elif args.command == "ios-target":
        output("target", ios_target())
    elif args.command == "native":
        native(args)
    elif args.command == "ios":
        configure_ios(args)
    elif args.command == "cleanup-ios":
        cleanup_ios(args)
    else:
        configure_android(args)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.SubprocessError, RuntimeError) as error:
        print("Guanyinma CI configuration failed: " + str(error), file=sys.stderr)
        raise SystemExit(1)
