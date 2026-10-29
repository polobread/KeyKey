#!/usr/bin/env python3
"""Exercise the real macOS Guanyinma adapter, without starting installed IMK.

Ordinary integration tests: no legacy engine, migration trace, user defaults, or
installed profile. Model bytes are checked before/after; user databases and the
executable live in a fresh temporary directory.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile

TESTS = Path(__file__).resolve().parent
LOADER = TESTS.parent
SOURCE = LOADER.parents[1]
CORE = SOURCE / "Guanyinma"
MODEL = SOURCE / "Distributions/Takao/CookedDatabase/KeyKey.db"


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def run(command, **kwargs):
    return subprocess.run(command, cwd=CORE, check=True, **kwargs)


def openssl_prefix(args):
    prefix = args.openssl_prefix
    if prefix is None:
        for candidate in (Path("/opt/homebrew/opt/openssl@3"), Path("/usr/local/opt/openssl@3")):
            if (candidate / "include/openssl/sha.h").is_file():
                prefix = candidate
                break
    if prefix is None and shutil.which("brew"):
        prefix = Path(subprocess.run(["brew", "--prefix", "openssl@3"], check=True,
                                     capture_output=True, text=True).stdout.strip())
    if prefix is None or not (prefix / "include/openssl/sha.h").is_file():
        raise RuntimeError("Archive oracle requires OpenSSL; pass --openssl-prefix or OPENSSL_PREFIX")
    return prefix


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=("integration", "all", "adapter", "archive"), default="integration")
    parser.add_argument("--cargo", default=os.environ.get("CARGO", "cargo"))
    parser.add_argument("--library", type=Path, help="Use an already built Guanyinma static library")
    parser.add_argument("--bundled-sqlite", action="store_true")
    parser.add_argument("--offline", action="store_true", help="Use only cached Cargo dependencies")
    parser.add_argument("--openssl-prefix", type=Path, default=os.environ.get("OPENSSL_PREFIX"),
                        help="OpenSSL used to compile the real legacy archive exporter oracle")
    parser.add_argument("--migration-reference", action="store_true",
                        help="Explicitly compile the legacy archive exporter for a manual migration comparison")
    args = parser.parse_args()
    if args.migration_reference and args.suite not in ("archive", "all"):
        parser.error("--migration-reference applies only to archive/all")
    if sys.platform != "darwin":
        parser.error("These native adapter tests require macOS Foundation and clang")
    controller = (LOADER / "OpenVanillaController.mm").read_text()
    hook = "GuanyinmaPrepareCandidatePanelForKey(&key, _context->candidateService())"
    dispatch = "isHandled = _context->handleKeyEvent(&key);"
    if controller.count(hook) != 1 or controller.index(hook) > controller.index(dispatch):
        raise RuntimeError("Native controller must prepare Rust keypad candidates before PV key dispatch")
    before = digest(MODEL)
    if args.library:
        library = args.library.resolve(strict=True)
    else:
        cargo = [args.cargo] if Path(args.cargo).is_file() else shlex.split(args.cargo)
        offline = ["--offline"] if args.offline else []
        build = cargo + ["build", "--locked", "--release", *offline]
        if args.bundled_sqlite:
            build += ["--features", "bundled-sqlite"]
        run(build)
        metadata = json.loads(run(cargo + [
            "metadata", "--locked", "--no-deps", "--format-version", "1", *offline,
        ], capture_output=True, text=True).stdout)
        library = Path(metadata["target_directory"]) / "release/libguanyinma.a"
    with tempfile.TemporaryDirectory(prefix="keykey-guanyinma-mac-tests-") as scratch:
        tmp = Path(scratch)
        frameworks = ["OpenVanilla", "PlainVanilla"]
        if args.migration_reference:
            frameworks += ["Formosa", "Manjusri", "Minotaur"]
        for framework in frameworks:
            path = tmp / (framework + ".framework")
            path.mkdir()
            (path / "Headers").symlink_to(SOURCE / "Frameworks" / framework / "Headers",
                                         target_is_directory=True)
        compiler = shlex.split(os.environ.get("CXX", "xcrun clang++"))
        if args.suite in ("all", "adapter"):
            tables = []
            c_compiler = shlex.split(os.environ.get("CC", "xcrun clang"))
            for name in ("VXHCTC2SCTable", "VXHCSC2TCTable"):
                table = tmp / (name + ".o")
                run(c_compiler + ["-std=c11", "-mmacosx-version-min=15.0", "-c", str(SOURCE / "ModulePackages/OVOFHanConvert" / (name + ".c")), "-o", str(table)])
                tables.append(str(table))
            executable = tmp / "GuanyinmaMacAdapterTests"
            run(compiler + [
                "-std=c++17", "-fno-objc-arc", "-fblocks", "-mmacosx-version-min=15.0",
                "-DOV_USE_SQLITE",
                "-Wno-deprecated-declarations", "-Wno-parentheses", "-Wno-dangling-else",
                "-F", str(tmp), "-I", str(LOADER), "-I", str(CORE / "include"),
                "-I", str(SOURCE / "Frameworks/PlainVanilla/Headers"),
                "-I", str(SOURCE / "ModulePackages/OVOFHanConvert"),
                "-I", str(SOURCE / "ModulePackages/OVOFFullWidthCharacter"),
                "-framework", "Foundation", "-framework", "Security", "-lsqlite3", "-liconv",
                str(TESTS / "GuanyinmaMacAdapterTests.mm"),
                str(LOADER / "GuanyinmaMacAdapter.mm"),
                str(SOURCE / "ModulePackages/OVIMMandarin/OVAFAssociatedPhrase.cpp"),
                str(SOURCE / "Frameworks/PlainVanilla/Source/Cocoa/PVPropertyList.mm"),
                str(SOURCE / "ModulePackages/OVOFHanConvert/OVOFHanConvert.cpp"),
                *tables,
                str(SOURCE / "ModulePackages/OVOFFullWidthCharacter/OVOFFullWidthCharacter.cpp"),
                str(library), "-o", str(executable),
            ])
            profiles = tmp / "profiles"
            profiles.mkdir()
            run([str(executable), str(MODEL), str(profiles)])
        if args.suite in ("all", "integration"):
            executable = tmp / "GuanyinmaMacPackageTests"
            run(compiler + [
                "-std=c++17", "-fno-objc-arc", "-fblocks", "-mmacosx-version-min=15.0",
                "-DOV_USE_SQLITE", "-Wno-deprecated-declarations", "-Wno-parentheses", "-Wno-dangling-else",
                "-F", str(tmp), "-I", str(LOADER), "-I", str(CORE / "include"),
                "-I", str(SOURCE / "Frameworks/PlainVanilla/Headers"),
                "-framework", "Foundation", "-lsqlite3", "-liconv",
                str(TESTS / "GuanyinmaMacPackageTests.mm"),
                str(LOADER / "GuanyinmaMacAdapter.mm"),
                str(SOURCE / "ModulePackages/OVIMMandarin/OVAFAssociatedPhrase.cpp"),
                str(SOURCE / "Frameworks/PlainVanilla/Source/Cocoa/PVPropertyList.mm"),
                str(library), "-o", str(executable),
            ])
            profiles = tmp / "package-profiles"
            profiles.mkdir()
            run([str(executable), str(MODEL), str(profiles)])
            run([sys.executable, str(TESTS / "run-guanyinma-administration-tests.py")])
        if args.suite in ("all", "archive"):
            archive_executable = tmp / "GuanyinmaMacArchiveTests"
            headers = []
            oracle = []
            if args.migration_reference:
                prefix = openssl_prefix(args)
                for framework in ("Manjusri", "Formosa", "Minotaur"):
                    headers += ["-I", str(SOURCE / "Frameworks" / framework / "Headers")]
                oracle = [
                    "-DGUANYINMA_MANUAL_LEGACY_ORACLE=1", "-I", str(prefix / "include"),
                    str(SOURCE / "Frameworks/Manjusri/Source/BPMFUserPhraseHelper.cpp"),
                    str(SOURCE / "Frameworks/Formosa/Source/Mandarin.cpp"),
                    str(SOURCE / "Frameworks/Minotaur/Source/Minotaur.cpp"),
                    str(prefix / "lib/libcrypto.dylib"),
                ]
            run(compiler + [
                "-std=c++17", "-fno-objc-arc", "-mmacosx-version-min=15.0", "-DOV_USE_SQLITE",
                "-Wno-deprecated-declarations", "-Wno-parentheses",
                "-Wno-dangling-else", "-F", str(tmp), "-I", str(LOADER), "-I", str(CORE / "include"),
                *headers,
                "-framework", "Foundation", "-lsqlite3", "-liconv",
                str(TESTS / "GuanyinmaMacArchiveTests.mm"),
                str(LOADER / "GuanyinmaMacArchive.mm"),
                *oracle, str(library), "-o", str(archive_executable),
            ])
            archives = tmp / "archives"
            archives.mkdir()
            run([str(archive_executable), str(MODEL), str(archives)])
    if digest(MODEL) != before:
        raise RuntimeError("Canonical KeyKey.db changed during native adapter tests")
    print("Native adapter tests passed; canonical KeyKey.db bytes unchanged.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.CalledProcessError, RuntimeError) as error:
        print("Native adapter verification failed:", error, file=sys.stderr)
        raise SystemExit(1)
