#!/usr/bin/env python3
"""Headless native associated-phrase routing smoke; no IMK/profile/UI/baseline.

Runs the actual macOS Rust adapter and OpenVanilla filter against fresh SQLite
fixtures. Uses an explicitly supplied library and never builds Rust or modifies
KeyKey.db. Candidate panels here are in-memory PlainVanilla state, no windows.
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("This native adapter smoke requires macOS Foundation and clang")
    library = args.library.resolve(strict=True)
    before = hashlib.sha256(MODEL.read_bytes()).hexdigest()
    report = {"status": "failed", "steps": []}
    try:
        with tempfile.TemporaryDirectory(prefix="keykey-associated-phrases-") as directory:
            tmp = Path(directory)
            for name in ("OpenVanilla", "PlainVanilla"):
                framework = tmp / (name + ".framework")
                framework.mkdir()
                (framework / "Headers").symlink_to(SOURCE / "Frameworks" / name / "Headers", target_is_directory=True)
            executable = tmp / "associated-phrases"
            command = shlex.split(os.environ.get("CXX", "xcrun clang++")) + [
                "-std=c++17", "-fno-objc-arc", "-fblocks", "-mmacosx-version-min=15.0",
                "-DOV_USE_SQLITE",
                "-Wno-deprecated-declarations", "-Wno-parentheses", "-Wno-dangling-else",
                "-F", str(tmp), "-I", str(LOADER), "-I", str(CORE / "include"),
                "-I", str(SOURCE / "Frameworks/PlainVanilla/Headers"),
                "-I", str(SOURCE / "ModulePackages/OVIMMandarin"),
                "-framework", "Foundation", "-lsqlite3", "-liconv",
                str(TESTS / "GuanyinmaAssociatedPhraseTests.mm"),
                str(LOADER / "GuanyinmaMacAdapter.mm"),
                str(SOURCE / "ModulePackages/OVIMMandarin/OVAFAssociatedPhrase.cpp"),
                str(SOURCE / "Frameworks/PlainVanilla/Source/Cocoa/PVPropertyList.mm"),
                str(library), "-o", str(executable),
            ]
            for name, command in (("compile", command), ("run", [str(executable), str(MODEL), str(tmp)])):
                result = subprocess.run(command, cwd=CORE, capture_output=True, text=True)
                report["steps"].append({"name": name, "command": command, "returncode": result.returncode,
                                        "stdout": result.stdout, "stderr": result.stderr})
                if result.stderr:
                    print(result.stderr, end="", file=sys.stderr)
                if result.returncode:
                    raise RuntimeError(f"{name} failed: {result.stdout}")
                if name == "run":
                    report["result"] = json.loads(result.stdout)
            if hashlib.sha256(MODEL.read_bytes()).hexdigest() != before:
                raise RuntimeError("Canonical model bytes changed")
            report["status"] = "passed"
            print(json.dumps(report["result"]))
        return 0
    except (OSError, RuntimeError, ValueError) as error:
        report["error"] = str(error)
        print(error, file=sys.stderr)
        return 1
    finally:
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
