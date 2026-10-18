#!/usr/bin/env python3
"""Exercise the real macOS Cangjie controller against an isolated plist."""
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
preferences = root / "Source/PreferenceApplications/OSX"
for locale in ("English", "zh_TW", "zh_CN"):
    document = ET.parse(preferences / f"{locale}.lproj/MainMenu.xib")
    assert document.find(".//button[@id='cangjie-prefix']") is not None
    assert document.find(".//outlet[@property='_prefixCandidatesCheckBox'][@destination='cangjie-prefix']") is not None
with tempfile.TemporaryDirectory(prefix="keykey-cangjie-preferences-") as directory:
    executable = Path(directory) / "preferences-test"
    subprocess.run(["xcrun", "clang", "-fno-objc-arc", "-w", "-framework", "Cocoa",
                    '-DOPENVANILLA_DO_CONNECTION_NAME=@"KeyKeyCangjieIsolatedTest"',
                    "-I", str(root / "Source/Loaders/OSX-IMK"),
                    "-I", str(root / "Source/Frameworks/LFExtensions"),
                    str(preferences / "TakaoCangjie.m"),
                    str(root / "Source/Loaders/OSX-IMK/Tests/MacCangjiePreferencesTests.m"),
                    "-o", str(executable)], check=True)
    subprocess.run([str(executable), str(Path(directory) / "cangjie.plist")], check=True)
