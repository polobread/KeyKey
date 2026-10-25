#!/usr/bin/env python3
"""Compare actual macOS modules with the Rust adapter, without migration fixtures."""
import argparse
import hashlib
import importlib.util
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
spec = importlib.util.spec_from_file_location("native_driver", TESTS / "run-guanyinma-tests.py")
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--group", choices=("case","layouts","edits","controls","tables","caps","all"), default="all")
    parser.add_argument("--openssl-prefix", type=Path, default=os.environ.get("OPENSSL_PREFIX"))
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("Native macOS modules require Foundation and Apple clang")
    library = args.library.resolve(strict=True)
    prefix = driver.openssl_prefix(args)
    before = digest(MODEL)
    with tempfile.TemporaryDirectory(prefix="guanyinma-native-behavior-") as directory:
        tmp = Path(directory)
        for framework in ("OpenVanilla","PlainVanilla","Formosa","Manjusri","Minotaur"):
            path = tmp / (framework + ".framework")
            path.mkdir()
            (path / "Headers").symlink_to(SOURCE / "Frameworks" / framework / "Headers", target_is_directory=True)
        cmd = shlex.split(os.environ.get("CXX", "xcrun clang++")) + [
            "-std=c++17","-fno-objc-arc","-fblocks","-mmacosx-version-min=15.0",
            "-DKEYKEY_ENABLE_GUANYINMA=1","-DOV_USE_SQLITE",
            "-DOVIMTRADITIONALMANDARIN_USE_ABSOLUTE_ORDER_QUERY_STRING=1",
            '-DOVIMSMARTMANDARIN_IDENTIFIER="SmartMandarin"',
            '-DOVIMTRADITIONALMANDARIN_IDENTIFIER="TraditionalMandarin"',
            '-DOVIMMANDARIN_IDENTIFIER="Mandarin"',
            '-DOVIMMANDARIN_PUNCTUATIONS_TABLE_PREFIX="Punctuations"',
            "-Wno-deprecated-declarations","-Wno-parentheses","-Wno-dangling-else","-Wno-extra-tokens",
            "-F",str(tmp),"-I",str(LOADER),"-I",str(CORE / "include"),
            "-I",str(SOURCE / "Frameworks/PlainVanilla/Headers"),
            "-I",str(SOURCE / "Frameworks/Manjusri/Headers"),
            "-I",str(SOURCE / "Frameworks/Formosa/Headers"),
            "-I",str(SOURCE / "Frameworks/Minotaur/Headers"),
            "-I",str(SOURCE / "ModulePackages/OVIMMandarin"),
            "-I",str(SOURCE / "ModulePackages/OVIMGeneric"),
            "-I",str(prefix / "include"),
            "-framework","Foundation","-framework","Security","-lsqlite3","-liconv",
            str(TESTS / "GuanyinmaMacNativeBehaviorTests.mm"),
            str(SOURCE / "ModulePackages/OVIMMandarin/OVIMSmartMandarin.cpp"),
            str(SOURCE / "ModulePackages/OVIMMandarin/OVIMTraditionalMandarin.cpp"),
            str(SOURCE / "ModulePackages/OVIMGeneric/OVIMGeneric.cpp"),
            str(SOURCE / "Frameworks/Manjusri/Source/Node.cpp"),
            str(SOURCE / "Frameworks/Manjusri/Source/BPMFUserPhraseHelper.cpp"),
            str(SOURCE / "Frameworks/Formosa/Source/Mandarin.cpp"),
            str(SOURCE / "Frameworks/Minotaur/Source/Minotaur.cpp"),
            str(prefix / "lib/libcrypto.dylib"),
            str(LOADER / "GuanyinmaMacAdapter.mm"),
            str(LOADER / "GuanyinmaMacCoreSelection.mm"),
            str(SOURCE / "Frameworks/PlainVanilla/Source/Cocoa/PVPropertyList.mm"),
            str(library),"-o",str(tmp / "native-oracle"),
        ]
        subprocess.run(cmd, check=True, cwd=CORE)
        profiles = tmp / "profiles"
        profiles.mkdir()
        subprocess.run([str(tmp / "native-oracle"),str(MODEL),str(profiles),args.group], check=True, cwd=CORE)
    if digest(MODEL) != before:
        raise RuntimeError("Canonical KeyKey.db bytes changed")
    print("Native behavior oracle passed; canonical DB bytes unchanged.")
if __name__ == "__main__":
    try: main()
    except (OSError, subprocess.CalledProcessError, RuntimeError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
