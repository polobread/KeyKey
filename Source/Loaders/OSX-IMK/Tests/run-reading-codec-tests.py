#!/usr/bin/env python3
"""Compare Guanyinma's stateless codec with the actual Formosa/Manjusri sources.

Ordinary headless native contract test: no model, database/session, preferences,
installed input method, keyboard events or functional migration baseline.
Compiles in a fresh temporary directory and uses an explicitly supplied library.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

TESTS = Path(__file__).resolve().parent
LOADER = TESTS.parent
SOURCE = LOADER.parents[1]
CORE = SOURCE / "Guanyinma"


def openssl_prefix(requested):
    candidates = ([Path(requested)] if requested else []) + [
        Path("/opt/homebrew/opt/openssl@3"), Path("/usr/local/opt/openssl@3")]
    for prefix in candidates:
        if (prefix / "include/openssl/sha.h").is_file() and (prefix / "lib/libcrypto.dylib").is_file():
            return prefix
    if requested:
        raise RuntimeError("--openssl-prefix must contain headers and lib/libcrypto.dylib")
    if shutil.which("brew"):
        prefix = Path(subprocess.run(["brew", "--prefix", "openssl@3"], check=True,
                                    capture_output=True, text=True).stdout.strip())
        return openssl_prefix(prefix)
    raise RuntimeError("Native codec oracle requires OpenSSL; pass --openssl-prefix or OPENSSL_PREFIX")


def run_step(report, name, command):
    step = {"name": name, "command": command, "returncode": None}
    report["steps"].append(step)
    started = time.monotonic()
    try:
        result = subprocess.run(command, cwd=CORE, capture_output=True, text=True)
        step.update(returncode=result.returncode, stdout=result.stdout, stderr=result.stderr)
        if result.stderr:
            print(result.stderr, end="", file=sys.stderr)
        if result.returncode:
            if result.stdout:
                print(result.stdout, end="")
            raise RuntimeError(f"{name} failed with exit code {result.returncode}")
        return result.stdout
    finally:
        step["elapsed_seconds"] = round(time.monotonic() - started, 6)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, required=True,
                        help="Absolute path to an already built native Guanyinma static library")
    parser.add_argument("--openssl-prefix", type=Path, default=os.environ.get("OPENSSL_PREFIX"))
    parser.add_argument("--report", type=Path, help="Write a JSON execution report, including failures")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("This native source oracle requires macOS Foundation and clang")
    if not args.library.is_absolute():
        parser.error("--library must be an absolute path; this runner does not build Rust")
    report = {"schema_version": 1, "kind": "guanyinma_native_reading_codec", "status": "failed",
              "recorded_at": datetime.now(timezone.utc).isoformat(), "steps": [],
              "library": str(args.library), "executed": False, "error": None}
    try:
        library = args.library.resolve(strict=True)
        prefix = openssl_prefix(args.openssl_prefix)
        with tempfile.TemporaryDirectory(prefix="keykey-guanyinma-reading-codec-") as scratch:
            tmp = Path(scratch)
            for framework in ("OpenVanilla", "PlainVanilla", "Formosa", "Manjusri", "Minotaur"):
                path = tmp / (framework + ".framework")
                path.mkdir()
                (path / "Headers").symlink_to(SOURCE / "Frameworks" / framework / "Headers",
                                             target_is_directory=True)
            executable = tmp / "GuanyinmaReadingCodecTests"
            compiler = shlex.split(os.environ.get("CXX", "xcrun clang++"))
            headers = []
            for framework in ("Manjusri", "Formosa", "Minotaur"):
                headers += ["-I", str(SOURCE / "Frameworks" / framework / "Headers")]
            command = compiler + [
                "-std=c++17", "-fno-objc-arc", "-mmacosx-version-min=15.0", "-DOV_USE_SQLITE",
                "-DKEYKEY_ENABLE_GUANYINMA=1", "-Wno-deprecated-declarations", "-Wno-parentheses",
                "-Wno-dangling-else", "-F", str(tmp), "-I", str(LOADER), "-I", str(CORE / "include"),
                *headers, "-I", str(prefix / "include"),
                "-framework", "Foundation", "-lsqlite3", "-liconv",
                str(TESTS / "GuanyinmaReadingCodecTests.mm"),
                str(SOURCE / "Frameworks/Manjusri/Source/BPMFUserPhraseHelper.cpp"),
                str(SOURCE / "Frameworks/Formosa/Source/Mandarin.cpp"),
                str(SOURCE / "Frameworks/Minotaur/Source/Minotaur.cpp"),
                str(prefix / "lib/libcrypto.dylib"), str(library), "-o", str(executable),
            ]
            run_step(report, "compile_actual_legacy_sources", command)
            result = run_step(report, "run_native_codec", [str(executable)])
            report["result"] = json.loads(result)
            report.update(status="passed", executed=True)
            print("Native reading codec passed: " + json.dumps(report["result"], sort_keys=True))
        return 0
    except (OSError, RuntimeError, subprocess.CalledProcessError, ValueError) as error:
        report["error"] = str(error)
        print("Native reading codec verification failed: " + str(error), file=sys.stderr)
        return 1
    finally:
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
