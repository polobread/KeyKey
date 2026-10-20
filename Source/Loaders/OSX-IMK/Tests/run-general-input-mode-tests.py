#!/usr/bin/env python3
"""Exercise the real general controller with isolated profiles and localized nib geometry."""
from pathlib import Path
import argparse
import json
import plistlib
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[4]
prefs = root / "Source/PreferenceApplications/OSX"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--snapshots", type=Path)
args = parser.parse_args()
if args.snapshots:
    args.snapshots.mkdir(parents=True, exist_ok=True)

def rect(node):
    frame = node.find("./rect[@key='frame']")
    return [float(frame.get(key, 0)) for key in ["x", "y", "width", "height"]]

with tempfile.TemporaryDirectory(prefix="keykey-general-mode-") as scratch:
    tmp = Path(scratch)
    contents = tmp / "PreferencesTests.app/Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "Resources").mkdir()
    (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier":"io.github.polobread.GeneralInputModeTest", "CFBundleExecutable":"Test", "CFBundlePackageType":"APPL"}))
    for locale in ["English", "zh_TW", "zh_CN"]:
        resources = contents / "Resources" / (locale + ".lproj")
        resources.mkdir()
        shutil.copy2(prefs / (locale + ".lproj/Localizable.strings"), resources)
    binary = contents / "MacOS/Test"
    subprocess.run(["xcrun", "clang", "-fno-objc-arc", "-Wno-deprecated-declarations", "-Wno-objc-method-access", "-Wno-incompatible-pointer-types", "-framework", "Cocoa", "-framework", "Carbon",
                    '-DOPENVANILLA_DO_CONNECTION_NAME=@"GeneralInputModeIsolatedTest"',
                    "-I", str(root / "Source/Loaders/OSX-IMK"), "-I", str(root / "Source/Frameworks/LFExtensions"),
                    str(prefs / "TakaoGlobal.m"), str(root / "Source/Loaders/OSX-IMK/Tests/MacGeneralInputModeTests.m"), "-o", str(binary)], check=True)
    for locale, language in [("English", "en"), ("zh_TW", "zh-TW"), ("zh_CN", "zh-CN")]:
        document = ET.parse(prefs / (locale + ".lproj/MainMenu.xib"))
        general = document.find(".//customView[@userLabel='General View']")
        controller = document.find(".//customObject[@customClass='TakaoGlobal']")
        children = []
        for child in general.find("subviews"):
            cell = child.find("./*[@key='cell']")
            entry = {"id":child.get("id"), "kind":child.tag, "rect":rect(child), "title":cell.get("title", "") if cell is not None else ""}
            if child.tag == "scrollView": entry["table"] = child.find(".//tableView").get("id")
            children.append(entry)
        layout = {"rect":rect(general), "children":children, "outlets":{item.get("property"):item.get("destination") for item in controller.findall("./connections/outlet")}}
        layout_path = tmp / (locale + ".json")
        layout_path.write_text(json.dumps(layout))
        snapshot = (args.snapshots or tmp) / ("general-input-mode-" + locale + ".png")
        subprocess.run([str(binary), str(layout_path), str(tmp / (locale + ".plist")), str(snapshot), "-AppleLanguages", "(" + language + ")"], check=True)
