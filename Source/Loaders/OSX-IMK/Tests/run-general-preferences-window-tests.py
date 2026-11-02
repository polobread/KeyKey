#!/usr/bin/env python3
"""Exercise the real localized preference NIB, toolbar, and pane sizing in isolation."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[4]
PREFS = ROOT / "Source/PreferenceApplications/OSX"
TESTS = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--snapshots", type=Path)
parser.add_argument("--global-source", type=Path, default=PREFS / "TakaoGlobal.m")
parser.add_argument("--preference-source", type=Path, default=PREFS / "TakaoPreference.m")
args = parser.parse_args()
snapshots = args.snapshots.resolve() if args.snapshots else None
if snapshots:
    snapshots.mkdir(parents=True, exist_ok=True)

with tempfile.TemporaryDirectory(prefix="keykey-general-window-") as scratch:
    tmp = Path(scratch)
    contents = tmp / "PreferencesWindowTests.app/Contents"
    resources = contents / "Resources"
    binary = contents / "MacOS/Test"
    binary.parent.mkdir(parents=True)
    resources.mkdir()
    (contents / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "io.github.polobread.GeneralPreferencesWindowTest",
        "CFBundleExecutable": "Test", "CFBundlePackageType": "APPL",
        "NSPrincipalClass": "NSApplication",
    }))
    for image in (PREFS / "Images").glob("*.tiff"):
        shutil.copy2(image, resources)
    for locale in ("English", "zh_TW", "zh_CN"):
        localized = resources / (locale + ".lproj")
        localized.mkdir()
        shutil.copy2(PREFS / (locale + ".lproj/Localizable.strings"), localized)
        document = ET.parse(PREFS / (locale + ".lproj/MainMenu.xib"))
        for node in document.iter():
            custom = node.get("customClass")
            if custom == "TakaoPreference":
                node.set("customClass", "WindowTestPreference")
            elif custom == "TakaoGlobal":
                node.set("customClass", "WindowTestGlobal")
            elif custom == "TakaoKeyboardLayoutPopUpButton":
                node.set("customClass", "NSPopUpButton")
            elif custom and custom.startswith("Takao") and custom not in ("TakaoWindow", "TakaoColorPopUpButton"):
                if node.tag != "customObject":
                    raise RuntimeError(f"Unrecognized custom view {custom}")
                node.set("customClass", "QuietController")
        xib = tmp / (locale + ".xib")
        document.write(xib, encoding="utf-8", xml_declaration=True)
        subprocess.run(["xcrun", "ibtool", "--compile", str(localized / "LayoutMain.nib"), str(xib)], check=True,
                       stdout=subprocess.DEVNULL)
    baseline_defines = ["-DWINDOW_TITLE_HEIGHT=78"] if "WINDOW_TITLE_HEIGHT" in args.preference_source.read_text() else []
    subprocess.run([
        "xcrun", "clang", "-fno-objc-arc", "-fblocks",
        "-Wno-deprecated-declarations", "-Wno-objc-method-access", "-Wno-incompatible-pointer-types",
        '-DOPENVANILLA_DO_CONNECTION_NAME=@"GeneralPreferencesWindowIsolatedTest"',
        "-I", str(PREFS), "-I", str(ROOT / "Source/Loaders/OSX-IMK"),
        "-I", str(ROOT / "Source/Frameworks/LFExtensions"),
        "-framework", "Cocoa", "-framework", "Carbon", *baseline_defines,
        str(args.global_source.resolve()), str(args.preference_source.resolve()),
        str(PREFS / "TakaoPreference_Toolbar.m"), str(PREFS / "TakaoWindow.m"),
        str(TESTS / "MacGeneralPreferencesWindowTests.m"), "-o", str(binary),
    ], check=True)
    failed = False
    for locale, language in (("English", "en"), ("zh_TW", "zh-TW"), ("zh_CN", "zh-CN")):
        for service in ("nil", "throw"):
            name = f"{locale}-{service}"
            output = (snapshots or tmp) / name
            output.mkdir(exist_ok=True)
            env = os.environ.copy()
            result = subprocess.run([
                str(binary), str(tmp / (name + ".plist")), str(output), name, service,
                "-AppleLanguages", "(" + language + ")",
            ], env=env, text=True)
            failed |= result.returncode != 0
    raise SystemExit(1 if failed else 0)
