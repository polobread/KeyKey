#!/usr/bin/env python3
"""Isolated AppKit regression for symbol startup ordering; no installed IMK access."""
import argparse
import json
import os
import sys
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
LOADER = ROOT / "Source/Loaders/OSX-IMK"

def run(*args):
    subprocess.run([str(a) for a in args], check=True, timeout=90)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-ref", help="Confirm the old failure against a Git revision as well")
    parser.add_argument("--snapshots", type=Path, help="Save isolated AppKit view renders")
    scenarios = ["before", "after", "retry", "refresh", "empty", "emoji", "scale", "panel", "ordering"]
    parser.add_argument("--scenario", action="append", choices=scenarios, help="Run only selected affected cases")
    args = parser.parse_args()
    # Compiling the class in this fixture alone would miss its original omission
    # from the actual app target. Check the target's real source membership too.
    project = json.loads(subprocess.check_output([
        "plutil", "-convert", "json", "-o", "-", ROOT / "Source/Takao.xcodeproj/project.pbxproj"]))
    objects = project["objects"]
    target = next(obj for obj in objects.values()
                  if obj.get("isa") == "PBXNativeTarget" and obj.get("name") == "Takao (Loader OSX-IMK)")
    sources = [objects[file_id] for phase_id in target["buildPhases"]
               if objects[phase_id]["isa"] == "PBXSourcesBuildPhase"
               for file_id in objects[phase_id]["files"]]
    if not any(objects[source["fileRef"]].get("path") == "Loaders/OSX-IMK/CVDictionaryWindow.m" for source in sources):
        raise SystemExit("The IMK app target must compile CVDictionaryWindow.m")
    if args.snapshots:
        args.snapshots.mkdir(parents=True, exist_ok=True)
        os.environ["KEYKEY_SYMBOL_SNAPSHOT_DIR"] = str(args.snapshots.resolve())
    with tempfile.TemporaryDirectory(prefix="keykey-symbol-tests-") as scratch:
        tmp = Path(scratch)
        # Header-only framework layout; no dependency on a previous Xcode build.
        for name in ["OpenVanilla", "PlainVanilla"]:
            framework = tmp / (name + ".framework")
            framework.mkdir()
            (framework / "Headers").symlink_to(ROOT / "Source/Frameworks" / name / "Headers", target_is_directory=True)
        contents = tmp / "SymbolTests.app/Contents"
        resources = contents / "Resources"
        resources.mkdir(parents=True)
        (contents / "MacOS").mkdir()
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "io.github.polobread.KeyKeySymbolIsolatedTests",
            "CFBundleExecutable": "SymbolTests", "CFBundlePackageType": "APPL", "LSUIElement": True,
        }))
        for name in ["SymbolWindow", "SmileyView"]:
            run("xcrun", "ibtool", "--compile", resources / (name + ".nib"),
                LOADER / "Interface" / (name + ".xib"))
        run(sys.executable, LOADER / "Generate-EmojiResources.py", "--check",
            "--json-output", resources / "ExpectedEmoji.json")
        binary = contents / "MacOS/SymbolTests"
        database = ROOT / "Source/Distributions/Takao/CookedDatabase/KeyKey.db"
        def compile_controller(source, include_panel=True):
            panel_sources = [LOADER / "CVDictionaryWindow.m"] if include_panel else []
            run("xcrun", "clang++", "-x", "objective-c++", "-std=c++17", "-fno-objc-arc", "-fblocks",
                "-mmacosx-version-min=15.0", "-DOV_USE_SQLITE", "-Wno-incomplete-implementation", "-Wno-deprecated-declarations",
                "-Wno-parentheses", "-Wno-dangling-else",
                "-F", tmp, "-I", LOADER, "-I", ROOT / "Source/Frameworks/CareService/Headers",
                "-I", ROOT / "Source/Loaders/CrossPlatform", "-I", ROOT / "Source/Frameworks/LFExtensions",
                "-framework", "Cocoa", "-framework", "InputMethodKit", "-lsqlite3",
                source, *panel_sources, LOADER / "CVButtonViewController.mm", LOADER / "CVSmileyViewController.mm",
                LOADER / "Tests/MacSymbolControllerTests.mm", "-o", binary)
        if args.baseline_ref:
            baseline = tmp / "BaselineSymbolController.mm"
            baseline.write_bytes(subprocess.check_output([
                "git", "show", args.baseline_ref + ":Source/Loaders/OSX-IMK/CVSymbolController.mm"], cwd=ROOT))
            compile_controller(baseline, include_panel=False)
            # The same old controller succeeds when its observer exists first.
            run(binary, database, "after", "legacy")
            for scenario in ["before", "retry"]:
                result = subprocess.run([str(binary), str(database), scenario, "legacy"], capture_output=True, text=True, timeout=30)
                print(result.stdout, end="")
                if result.returncode != 1 or "the window contains every category" not in result.stderr:
                    raise SystemExit("Baseline did not reproduce the expected empty-window failure: " + result.stderr)
                print("EXPECTED BASELINE FAILURE: " + scenario, flush=True)
        compile_controller(LOADER / "CVSymbolController.mm")
        for scenario in args.scenario or scenarios:
            run(binary, database, scenario)

if __name__ == "__main__":
    main()
