#!/usr/bin/env python3
"""Shared desktop cases through isolated macOS controller methods and real PV/adapter.

No IMK server, installed input source, visible windows, global keys or personal
preferences. The text client is a UTF-16 test double, not a system IMK connection.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

TESTS = Path(__file__).resolve().parent
LOADER = TESTS.parent
SOURCE = LOADER.parents[1]
ROOT = SOURCE.parent
CORE = SOURCE / "Guanyinma"
MODEL = SOURCE / "Distributions/Takao/CookedDatabase/KeyKey.db"
FIXTURE = ROOT / "tests/desktop_input/cases.json"
METHODS = {"smart": "SmartMandarin", "traditional": "TraditionalMandarin",
           "cangjie": "Generic-cj-cin", "simplex": "Generic-simplex-cin"}
MAPPING = {
    "smart.shift_always_uppercase": ("SmartMandarin", "ShiftKeyAlwaysCommitUppercaseCharacters"),
    "smart.clear_composing_with_escape": ("SmartMandarin", "ClearComposingTextWithEsc"),
    "smart.space_opens_candidates": ("SmartMandarin", "ShowCandidateListWithSpace"),
    "smart.candidate_cursor_at_end": ("SmartMandarin", "CandidateCursorAtEndOfTargetBlock"),
    "smart.max_completed_syllables": ("SmartMandarin", "ComposingTextBufferSize"),
    "smart.candidate_selection_keys": ("SmartMandarin", "CandidateSelectionKeys"),
    "traditional_selection_keys": ("TraditionalMandarin", "CandidateSelectionKeys"),
    "table.maximum_radical_length": ("Generic-cj-cin", "MaximumRadicalLength"),
    "table.query_at_maximum": ("Generic-cj-cin", "ShouldCommitAtMaximumRadicalLength"),
    "table.clear_on_error": ("Generic-cj-cin", "ClearReadingBufferAtCompositionError"),
    "table.realtime": ("Generic-cj-cin", "ComposeWhileTyping"),
    "table.prefix": ("Generic-cj-cin", "PrefixCandidates"),
    "table.wildcard.one": ("Generic-cj-cin", "MatchOneChar"),
    "table.wildcard.many": ("Generic-cj-cin", "MatchZeroOrMoreChar"),
}
FIXED = {"layout": "standard", "behaviors.ignore_caps_lock_in_chinese": False,
         "smart.selection_returns_to_end": False, "smart.use_bigrams": True,
         "learning.candidate_overrides": True, "learning.bigrams": True,
         "learning.user_phrases": True}


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def extract(source, signature):
    """Match the existing run-input-mode-tests.py's verbatim method harness."""
    start = source.index(signature)
    opening = source.index("{", start)
    level, end = 1, opening + 1
    while level:
        level += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def build(args, directory):
    environment = os.environ.copy()
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    environment.update(SQLITE3_LIB_DIR=sdk + "/usr/lib", SQLITE3_INCLUDE_DIR=sdk + "/usr/include",
                       SQLITE3_STATIC="0", SQLITE3_NO_PKG_CONFIG="1")
    library = args.library
    if library is None:
        cargo = args.cargo or shutil.which("cargo") or str(Path.home() / ".cargo/bin/cargo")
        offline = ["--offline"] if args.offline else []
        subprocess.run([cargo, "build", "--locked", "--release", *offline], cwd=CORE, env=environment, check=True)
        metadata = json.loads(subprocess.check_output(
            [cargo, "metadata", "--locked", "--no-deps", "--format-version", "1", *offline], cwd=CORE, env=environment, text=True))
        library = Path(metadata["target_directory"]) / "release/libguanyinma.a"
    library = library.resolve(strict=True)
    for framework in ("OpenVanilla", "PlainVanilla"):
        path = directory / (framework + ".framework")
        path.mkdir()
        (path / "Headers").symlink_to(SOURCE / "Frameworks" / framework / "Headers", target_is_directory=True)
    controller = (LOADER / "OpenVanillaController.mm").read_text()
    functions = "\n".join(extract(controller, signature) for signature in (
        "static BOOL OVCIsInputMethodCtrlKey(", "static BOOL OVCShouldEnterEngine("))
    methods = "\n".join(extract(controller, signature) for signature in (
        "- (void)_updateClient:", "- (void)commitComposition:",
        "- (BOOL)_finishCompositionForModeSwitch:", "- (BOOL)_syncEnglishModeToCore:",
        "- (BOOL)_setEnglishMode:", "- (void)_handleShiftTap:", "- (BOOL)handleEvent:", "- (void)_resetUI",
        "- (void)toggleOutputFilterAction:"))
    generated = directory / "DesktopInputHost.mm"
    generated.write_text((TESTS / "DesktopInputHost.mm").read_text().replace(
        "// CONTROLLER_FUNCTIONS", functions).replace("// CONTROLLER_METHODS", methods))
    host = directory / "DesktopInputHost"
    command = shlex.split(os.environ.get("CXX", "xcrun clang++")) + [
        "-std=c++17", "-fno-objc-arc", "-fblocks", "-mmacosx-version-min=15.0", "-DOV_USE_SQLITE",
        "-Wno-deprecated-declarations", "-Wno-parentheses", "-Wno-dangling-else",
        "-F", str(directory), "-I", str(LOADER), "-I", str(CORE / "include"),
        "-I", str(SOURCE / "Frameworks/PlainVanilla/Headers"),
        "-I", str(SOURCE / "ModulePackages/OVOFFullWidthCharacter"),
        "-framework", "Cocoa", "-framework", "AudioToolbox", "-lsqlite3", "-liconv",
        str(generated), str(LOADER / "GuanyinmaMacAdapter.mm"), str(LOADER / "CVEncodingService.mm"),
        str(SOURCE / "ModulePackages/OVIMMandarin/OVAFAssociatedPhrase.cpp"),
        str(SOURCE / "Frameworks/PlainVanilla/Source/Cocoa/PVPropertyList.mm"),
        str(SOURCE / "ModulePackages/OVOFFullWidthCharacter/OVOFFullWidthCharacter.cpp"),
        str(library), "-o", str(host)]
    write_json(directory / "build.json", {"command": command, "library_sha256": digest(library),
               "controller_sha256": digest(LOADER / "OpenVanillaController.mm"),
               "generated_sha256": digest(generated)})
    subprocess.run(command, check=True, env=environment)
    return host


def configure(profile, prefs):
    unknown = set(prefs) - set(MAPPING) - set(FIXED) - {"method"}
    if unknown:
        raise ValueError(f"Unmapped shared preferences: {sorted(unknown)}")
    files = {
        "Loader": {"PrimaryInputMethod": METHODS[prefs["method"]], "ActivatedAroundFilters": [],
                   "ActivatedOutputFilters": [], "ToggleInputMethodWithControlBackslash": "false",
                   "DefaultInputMode": "Chinese", "ShouldPlaySoundOnTypingError": "false"},
        "SmartMandarin": {"KeyboardLayout": "Standard"},
        "TraditionalMandarin": {"KeyboardLayout": "Standard", "CandidateSelectionKeys": "12345678"},
        "Generic-cj-cin": {"ComposeWhileTyping": "false", "PrefixCandidates": "false", "ClearReadingBufferAtCompositionError": "false",
                           "ShouldCommitAtMaximumRadicalLength": "false", "UseDynamicFrequency": "false",
                           "UseSpaceAsFirstCandidateSelectionKey": "false", "SendFirstCandidateWithSpaceWithOnePageList": "true",
                           "MatchOneChar": "?", "MatchZeroOrMoreChar": "*"},
        "Generic-simplex-cin": {"UseDynamicFrequency": "false"},
    }
    for key, (group, name) in MAPPING.items():
        if key in prefs:
            value = prefs[key]
            files[group][name] = str(value).lower() if isinstance(value, bool) else str(value)
    for group, values in files.items():
        path = profile / (group + ".plist")
        path.write_bytes(plistlib.dumps(values))
        if plistlib.loads(path.read_bytes()) != values:
            raise AssertionError("Preference roundtrip differs: " + group)
    return files


def differences(actual, expected):
    errors = []
    for key, value in expected.items():
        if key in ("text", "preedit", "caret"):
            valid = actual.get(key) == value
        elif key == "combined":
            valid = actual["text"] + actual["preedit"] == value
        elif key == "committed_nonempty":
            valid = not value or bool(actual["text"])
        elif key == "max_preedit":
            valid = len(actual["preedit"]) <= value
        else:
            raise ValueError("Unknown expectation: " + key)
        if not valid:
            errors.append(f"{key}: expected {value!r}, actual {actual!r}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "Installer/local-builds/desktop-input-macos")
    parser.add_argument("--host", type=Path, help="Use a host built by this entry point")
    parser.add_argument("--library", type=Path, help="Use an existing Guanyinma staticlib")
    parser.add_argument("--cargo")
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--categories", default="settings,boundary,stability")
    parser.add_argument("--rounds", type=int, default=1)
    args = parser.parse_args()
    categories = args.categories.split(",")
    if sys.platform != "darwin" or args.rounds < 1 or set(categories) - {"settings", "boundary", "stability"}:
        parser.error("Requires macOS, known categories and a positive round count")
    fixture = json.loads(FIXTURE.read_text())
    before = digest(MODEL)
    if before != fixture["model_sha256"]:
        raise ValueError("Canonical model differs from shared fixture")
    args.output.mkdir(parents=True, exist_ok=True)
    out = Path(tempfile.mkdtemp(prefix="macos-pv-", dir=args.output.resolve()))
    host = args.host.resolve(strict=True) if args.host else build(args, out)
    write_json(out / "manifest.json", {
        "host": str(host), "host_sha256": digest(host), "model_sha256": before,
        "cases_sha256": digest(FIXTURE), "categories": categories, "stability_rounds": args.rounds,
        "evidence_layer": "verbatim controller methods / real PV loader and macOS adapter / test-owned UTF-16 client",
        "system_imk": False, "foreground_apps": False, "physical_keyboard": False,
        "native_bindings": {"ctrl+backslash": "controller language menu action", "shift+space": "PV width output-filter menu action"},
    })
    write_json(out / "shared-cases.json", fixture)
    control = {"id": "CONTROL-KEYBOARD-US", "category": "control", "preferences": {}, "control": True,
               "steps": [{"keys": list("su3cl3"), "expect": {"text": "su3cl3", "preedit": ""}}]}
    results = []
    for case in [control, *fixture["cases"]]:
        if case["category"] != "control" and case["category"] not in categories:
            continue
        prefs = {**fixture["baseline"], **fixture["profiles"]["shared-eight-key"], **case["preferences"]}
        reasons = [f"{key}={prefs[key]!r}: no equivalent macOS setting" for key, value in FIXED.items()
                   if key in prefs and prefs[key] != value]
        count = args.rounds if case["category"] == "stability" and not reasons else 1
        for number in range(1, count + 1):
            directory = out / f"{case['id']}-{number:03d}"
            profile = directory / "profile"
            profile.mkdir(parents=True)
            result = {"case": case["id"], "category": case["category"], "round": number, "status": "passed"}
            started = time.monotonic()
            if reasons:
                result.update(status="unsupported", reasons=reasons)
            else:
                try:
                    settings = configure(profile, prefs)
                    write_json(directory / "settings-readback.json", {"requested": prefs, "plist": settings})
                    write_json(directory / "reset-learning.json", {"strategy": "fresh process and fresh per-case profile",
                               "database_existed_before": (profile / "GuanyinmaUserData.db").exists()})
                    write_json(directory / "request.json", {**case, "method": METHODS[prefs["method"]]})
                    child = subprocess.run([str(host), str(directory / "request.json"), str(directory / "host.json"),
                                            str(MODEL), str(profile)], capture_output=True, timeout=45)
                    (directory / "host.stdout").write_bytes(child.stdout)
                    (directory / "host.stderr").write_bytes(child.stderr)
                    evidence = json.loads((directory / "host.json").read_text())
                    if child.returncode:
                        raise AssertionError(evidence.get("error", f"Host exited {child.returncode}"))
                    readback = {path.stem: plistlib.loads(path.read_bytes()) for path in profile.glob("*.plist")}
                    write_json(directory / "native-plist-readback.json", readback)
                    # PV may add its own defaults, but cannot lose requested module values.
                    for group, values in settings.items():
                        for key, value in values.items():
                            if readback[group].get(key) != value:
                                raise AssertionError(f"Native preference readback differs: {group}/{key}")
                    if case.get("scenario") == "focus":
                        expected = [{"text": "", "preedit": "你好"}, {"text": case["expected"]["app_a"], "preedit": ""},
                                    {"text": case["expected"]["app_b"], "preedit": ""}, {"text": case["expected"]["app_a"], "preedit": ""}]
                        result["scope"] = "two PV contexts/clients in one worker; system IMK and cross-App focus remain separate"
                    else:
                        expected = [step["expect"] for step in case["steps"]]
                    actual = evidence["checkpoints"]
                    if len(actual) != len(expected):
                        raise AssertionError("Checkpoint count differs")
                    comparisons = [{"expected": exp, "actual": act, "differences": differences(act, exp)}
                                   for act, exp in zip(actual, expected)]
                    write_json(directory / "checkpoints.json", comparisons)
                    errors = [f"checkpoint {index + 1}: {error}" for index, item in enumerate(comparisons) for error in item["differences"]]
                    if errors:
                        raise AssertionError("; ".join(errors))
                except Exception as error:
                    result.update(status="failed", error=str(error))
            result["seconds"] = round(time.monotonic() - started, 3)
            write_json(directory / "result.json", result)
            results.append(result)
            write_json(out / "results.json", results)
            print(f"{case['id']} round {number}: {result['status']}" + (": " + result["error"] if "error" in result else ""), flush=True)
    after = digest(MODEL)
    write_json(out / "model-integrity.json", {"before": before, "after": after, "unchanged": before == after})
    if after != before:
        raise RuntimeError("Canonical model changed during desktop tests")
    summary = {state: sum(item["status"] == state for item in results) for state in ("passed", "failed", "unsupported")}
    write_json(out / "summary.json", summary)
    print(json.dumps({"output": str(out), **summary}, ensure_ascii=False))
    return int(summary["failed"] != 0)


if __name__ == "__main__":
    sys.exit(main())
