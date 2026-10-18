#!/usr/bin/env python3
"""Build and run shared desktop Cangjie regressions without installing an IME."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="keykey-desktop-cangjie-") as directory:
    temporary = Path(directory)
    includes = []
    for name in ("OpenVanilla", "PlainVanilla"):
        headers = ROOT / "Source/Frameworks" / name / "Headers"
        includes.extend(["-I", str(headers)])
        if sys.platform == "darwin":
            framework = temporary / (name + ".framework")
            framework.mkdir()
            (framework / "Headers").symlink_to(headers)
    command = [os.environ.get("CXX", "c++"), "-std=c++17", "-w",
               "-DOV_USE_SQLITE", '-DOVIMGENERIC_IDENTIFIER_PREFIX="Generic"',
               *includes, "-I", str(ROOT / "Source/ModulePackages/OVIMGeneric")]
    if sys.platform == "darwin":
        command.extend(["-F", str(temporary)])
    executable = temporary / "desktop-cangjie"
    command.extend([str(ROOT / "tests/desktop_cangjie.cpp"),
                    str(ROOT / "Source/ModulePackages/OVIMGeneric/OVIMGeneric.cpp"),
                    str(ROOT / "Source/Loaders/Windows-TSF/WindowsTableInputMethod.cpp"),
                    "-lsqlite3", "-o", str(executable)])
    subprocess.run(command, check=True)
    for kind in ("shared", "windows"):
        profile = temporary / kind
        profile.mkdir()
        subprocess.run([str(executable),
                        str(ROOT / "Source/Distributions/Takao/CookedDatabase/KeyKey.db"),
                        str(profile), kind], check=True)
