#!/usr/bin/env python3
"""Compare native Generic and Guanyinma font policies without installed IMK.

Uses the read-only shared DB and temporary user stores; no migration baseline,
TIS changes, defaults or real input-method profile. --system-fonts additionally
checks the actual macOS CVEncodingService in the isolated test process.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

TESTS = Path(__file__).resolve().parent
LOADER = TESTS.parent
SOURCE = LOADER.parents[1]
CORE = SOURCE / "Guanyinma"
MODEL = SOURCE / "Distributions/Takao/CookedDatabase/KeyKey.db"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, **kwargs):
    return subprocess.run(command, cwd=CORE, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, help="Use an existing static library")
    parser.add_argument("--cargo", default=os.environ.get("CARGO", "cargo"))
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--system-fonts", action="store_true")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("macOS Cocoa and clang are required")
    before = digest(MODEL)
    if args.library:
        library = args.library.resolve(strict=True)
    else:
        cargo = [args.cargo] if Path(args.cargo).is_file() else shlex.split(args.cargo)
        offline = ["--offline"] if args.offline else []
        run(cargo + ["build", "--locked", "--release", *offline])
        metadata = json.loads(run(cargo + [
            "metadata", "--locked", "--no-deps", "--format-version", "1", *offline,
        ], capture_output=True, text=True).stdout)
        library = Path(metadata["target_directory"]) / "release/libguanyinma.a"
    with tempfile.TemporaryDirectory(prefix="keykey-guanyinma-glyph-tests-") as scratch:
        tmp = Path(scratch)
        for name in ("OpenVanilla", "PlainVanilla", "Formosa", "Manjusri", "Minotaur"):
            framework = tmp / (name + ".framework")
            framework.mkdir()
            (framework / "Headers").symlink_to(SOURCE / "Frameworks" / name / "Headers",
                                               target_is_directory=True)
        executable = tmp / "GuanyinmaMacGlyphTests"
        compiler = shlex.split(os.environ.get("CXX", "xcrun clang++"))
        run(compiler + [
            "-std=c++17", "-fno-objc-arc", "-fblocks", "-mmacosx-version-min=15.0",
            "-DKEYKEY_ENABLE_GUANYINMA=1", "-DOV_USE_SQLITE",
            "-Wno-deprecated-declarations", "-Wno-parentheses", "-Wno-dangling-else",
            "-F", str(tmp), "-I", str(LOADER), "-I", str(CORE / "include"),
            "-I", str(SOURCE / "Frameworks/PlainVanilla/Headers"),
            "-I", str(SOURCE / "ModulePackages/OVIMGeneric"),
            "-framework", "Cocoa", "-framework", "Security", "-lsqlite3", "-liconv",
            str(TESTS / "GuanyinmaMacGlyphTests.mm"),
            str(LOADER / "GuanyinmaMacAdapter.mm"),
            str(LOADER / "GuanyinmaMacCoreSelection.mm"),
            str(LOADER / "CVEncodingService.mm"),
            str(SOURCE / "ModulePackages/OVIMGeneric/OVIMGeneric.cpp"),
            str(SOURCE / "Frameworks/PlainVanilla/Source/Cocoa/PVPropertyList.mm"),
            str(library), "-o", str(executable),
        ])
        profiles = tmp / "profiles"
        profiles.mkdir()
        run([str(executable), str(MODEL), str(profiles)] +
            (["--system-fonts"] if args.system_fonts else []))
    if digest(MODEL) != before:
        raise RuntimeError("Canonical model changed during glyph oracle tests")
    print("Glyph oracle passed; canonical DB bytes unchanged.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
