#!/usr/bin/env python3
"""Run the real phrase-editor controller with isolated in-process service data."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / "Source"
EDITOR = SOURCE / "Utilities/PhraseEditor/OSX"
TEST = Path(__file__).with_name("MacPhraseEditorCoreTests.m")

with tempfile.TemporaryDirectory(prefix="keykey-phrase-editor-guards-") as directory:
    executable = Path(directory) / "PhraseEditorCoreTests"
    subprocess.run([
        "xcrun", "clang", "-fno-objc-arc", "-fblocks",
        "-Wno-deprecated-declarations", "-Wno-objc-method-access",
        "-Wno-incompatible-pointer-types", "-Wno-incompatible-pointer-types-discards-qualifiers",
        "-framework", "Cocoa", "-framework", "AddressBook",
        '-DOPENVANILLA_DO_CONNECTION_NAME=@"PhraseEditorIsolatedTest"',
        "-I", str(SOURCE / "Frameworks/LFExtensions"),
        str(EDITOR / "PEController.m"), str(EDITOR / "PESettingTableView.m"),
        str(TEST), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True, timeout=30)
