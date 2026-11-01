#!/usr/bin/env python3
"""Shared desktop contracts through a test-owned Windows native TSF host.

No SendInput, installed TIP activation, personal profiles or global key toggles.
This layer does not assert foreground application or physical keyboard coverage.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/desktop_input/cases.json"
METHODS = {"smart": "SmartMandarin", "traditional": "TraditionalMandarin",
           "cangjie": "Generic-cj-cin", "simplex": "Generic-simplex-cin"}
MAPPING = {
    "smart.shift_always_uppercase": ("SmartMandarin", "ShiftKeyAlwaysCommitUppercaseCharacters"),
    "behaviors.ignore_caps_lock_in_chinese": ("Loader", "IgnoreCapsLockInChinese"),
    "smart.clear_composing_with_escape": ("SmartMandarin", "ClearComposingTextWithEsc"),
    "smart.space_opens_candidates": ("SmartMandarin", "ShowCandidateListWithSpace"),
    "smart.candidate_cursor_at_end": ("SmartMandarin", "CandidateCursorAtEndOfTargetBlock"),
    "smart.max_completed_syllables": ("SmartMandarin", "ComposingTextBufferSize"),
    "smart.candidate_selection_keys": ("SmartMandarin", "CandidateSelectionKeys"),
    "traditional_selection_keys": ("TraditionalMandarin", "CandidateSelectionKeys"),
    "table.query_at_maximum": ("Generic-cj-cin", "ShouldCommitAtMaximumRadicalLength"),
    "table.clear_on_error": ("Generic-cj-cin", "ClearReadingBufferAtCompositionError"),
    "table.realtime": ("Generic-cj-cin", "ComposeWhileTyping"),
    "table.prefix": ("Generic-cj-cin", "PrefixCandidates"),
    "table.wildcard.one": ("Generic-cj-cin", "MatchOneChar"),
    "table.wildcard.many": ("Generic-cj-cin", "MatchZeroOrMoreChar"),
}
FIXED = {"layout": "standard", "smart.selection_returns_to_end": False,
         "smart.use_bigrams": True, "learning.candidate_overrides": True,
         "learning.bigrams": True, "learning.user_phrases": True}


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def scalar(value):
    return str(value).lower() if isinstance(value, bool) else str(value)


def configure(profile, prefs):
    files = {
        "Loader": {"PrimaryInputMethod": METHODS[prefs["method"]], "DefaultInputMode": "Chinese",
                   "ToggleInputMethodWithControlBackslash": "true", "SimplifiedChineseOutput": "false",
                   "ShouldPlaySoundOnTypingError": "false", "SymbolPanelShortcutEnabled": "false"},
        "SmartMandarin": {"KeyboardLayout": "Standard", "ClearComposingTextWithEsc": "false",
                          "ClearComposingTextWithEscUserChoice": "false"},
        "TraditionalMandarin": {"KeyboardLayout": "Standard", "CandidateSelectionKeys": "12345678"},
        "Generic-cj-cin": {"ComposeWhileTyping": "false", "PrefixCandidates": "false", "ClearReadingBufferAtCompositionError": "false",
                           "ShouldCommitAtMaximumRadicalLength": "false", "UseDynamicFrequency": "false",
                           "UseSpaceAsFirstCandidateSelectionKey": "false", "SendFirstCandidateWithSpaceWithOnePageList": "true",
                           "MatchOneChar": "?", "MatchZeroOrMoreChar": "*"},
        "AssociatedPhrase": {"EnabledCollections": ""},
    }
    unknown = set(prefs) - set(MAPPING) - set(FIXED) - {"method", "table.maximum_radical_length"}
    if unknown:
        raise ValueError(f"Unmapped shared preferences: {sorted(unknown)}")
    for key, (group, name) in MAPPING.items():
        if key in prefs:
            files[group][name] = scalar(prefs[key])
    files["SmartMandarin"]["ClearComposingTextWithEscUserChoice"] = files["SmartMandarin"]["ClearComposingTextWithEsc"]
    readback = {}
    for group, settings in files.items():
        root = ET.Element("plist", version="1.0")
        dictionary = ET.SubElement(root, "dict")
        for key, value in settings.items():
            ET.SubElement(dictionary, "key").text = key
            ET.SubElement(dictionary, "string").text = value
        suffix = "" if group == "Loader" else "." + group
        path = profile / ("com.polobread.chichi77-keykey.windows" + suffix + ".plist")
        ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)
        children = list(ET.parse(path).getroot().find("dict"))
        actual = {children[i].text: children[i + 1].text or "" for i in range(0, len(children), 2)}
        if actual != settings:
            raise AssertionError("Preference readback differs: " + group)
        readback[group] = actual
    return readback


def unsupported(prefs):
    reasons = [f"{key}={prefs[key]!r}: no equivalent Windows setting" for key, value in FIXED.items()
               if key in prefs and prefs[key] != value]
    if prefs["method"] == "smart" and len(prefs["smart.candidate_selection_keys"]) != 8:
        reasons.append("Windows Smart adapter supports eight selection keys; nine keys fall back to eight")
    if "table.maximum_radical_length" in prefs and prefs["table.maximum_radical_length"] != 5:
        reasons.append("Windows Cangjie adapter fixes maximum_radical_length=5")
    return reasons


def differences(actual, expected):
    errors = []
    for key, value in expected.items():
        if key in ("text", "preedit", "caret") and actual.get(key) != value:
            errors.append(f"{key}: expected {value!r}, actual {actual.get(key)!r}")
        elif key == "combined" and actual["text"] + actual["preedit"] != value:
            errors.append(f"combined: expected {value!r}, actual {(actual['text'] + actual['preedit'])!r}")
        elif key == "committed_nonempty" and value and not actual["text"]:
            errors.append("No text committed at the boundary")
        elif key == "max_preedit" and len(actual["preedit"]) > value:
            errors.append(f"Preedit exceeds {value} Unicode characters")
        elif key not in {"text", "preedit", "caret", "combined", "committed_nonempty", "max_preedit"}:
            errors.append("Unknown expectation: " + key)
    return errors


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--categories", default="settings,boundary,stability")
    parser.add_argument("--rounds", type=int, default=1)
    args = parser.parse_args()
    categories = args.categories.split(",")
    if args.rounds < 1 or not categories or set(categories) - {"settings", "boundary", "stability"}:
        parser.error("Invalid categories or round count")
    host = args.host.resolve()
    model = host.parent / "Databases/KeyKey.db"
    fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
    model_hash = hashlib.sha256(model.read_bytes()).hexdigest()
    if model_hash != fixture["model_sha256"]:
        raise ValueError("Staged Windows model differs from the shared fixture")
    # A new directory on every invocation preserves the first failing evidence.
    args.output.mkdir(parents=True, exist_ok=True)
    import tempfile
    out = Path(tempfile.mkdtemp(prefix="windows-tsf-", dir=args.output.resolve()))
    write_json(out / "manifest.json", {
        "host": str(host), "host_sha256": hashlib.sha256(host.read_bytes()).hexdigest(),
        "model_sha256": model_hash, "cases_sha256": hashlib.sha256(FIXTURE.read_bytes()).hexdigest(),
        "categories": categories, "stability_rounds": args.rounds,
        "evidence_layer": "native TSF context / test-owned ACP document / thread-local injected keyboard state",
        "foreground_apps": "not exercised", "physical_keyboard": "not exercised",
    })
    control = {"id": "CONTROL-KEYBOARD-US", "category": "control", "preferences": {}, "control": True,
               "steps": [{"keys": list("su3cl3"), "expect": {"text": "su3cl3", "preedit": ""}}]}
    results = []
    for case in [control, *fixture["cases"]]:
        if case["category"] != "control" and case["category"] not in categories:
            continue
        prefs = {**fixture["baseline"], **fixture["profiles"]["shared-eight-key"], **case["preferences"]}
        reasons = unsupported(prefs)
        rounds = args.rounds if case["category"] == "stability" and not reasons else 1
        for number in range(1, rounds + 1):
            directory = out / f"{case['id']}-{number:03d}"
            profile = directory / "profile"
            profile.mkdir(parents=True)
            result = {"case": case["id"], "round": number, "status": "passed", "category": case["category"]}
            started = time.monotonic()
            if reasons:
                result.update(status="unsupported", reasons=reasons)
            else:
                try:
                    settings = configure(profile, prefs)
                    write_json(directory / "settings-readback.json", {"requested": prefs, "plist": settings})
                    write_json(directory / "reset-learning.json", {"strategy": "fresh process and fresh per-case profile",
                               "database_existed_before": (profile / "GuanyinmaUserData.db").exists()})
                    request = {**case, "method": METHODS[prefs["method"]]}
                    write_json(directory / "request.json", request)
                    child = subprocess.run([str(host), str(directory / "request.json"), str(directory / "host.json")],
                                           env={**os.environ, "KEYKEY_TSF_TEST_PROFILE_DIR": str(profile), "PYTHONUTF8": "1"},
                                           capture_output=True, timeout=45)
                    (directory / "host.stdout").write_bytes(child.stdout)
                    (directory / "host.stderr").write_bytes(child.stderr)
                    evidence = json.loads((directory / "host.json").read_text(encoding="utf-8"))
                    if child.returncode:
                        raise AssertionError(evidence.get("error", f"Host exited {child.returncode}"))
                    if evidence["ignore_caps_lock_in_chinese"] != prefs["behaviors.ignore_caps_lock_in_chinese"]:
                        raise AssertionError("Windows frontend Caps Lock readback differs")
                    if prefs["method"] == "cangjie":
                        effective = evidence["native_table_settings"]
                        for key, fallback in (("table.realtime", False), ("table.prefix", False), ("table.clear_on_error", False)):
                            if effective[key] != prefs.get(key, fallback):
                                raise AssertionError(f"Windows frontend table readback differs: {key}")
                    if case.get("scenario") == "focus":
                        expected = [{"text": "", "preedit": "你好"}, {"text": case["expected"]["app_a"], "preedit": ""},
                                    {"text": case["expected"]["app_b"], "preedit": ""}, {"text": case["expected"]["app_a"], "preedit": ""}]
                        result["scope"] = "two TSF documents in one worker; cross-App foreground test remains pending"
                    else:
                        expected = [step["expect"] for step in case["steps"]]
                    actual = evidence["checkpoints"]
                    if len(actual) != len(expected):
                        raise AssertionError(f"Expected {len(expected)} checkpoints, got {len(actual)}")
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
    summary = {state: sum(item["status"] == state for item in results) for state in ("passed", "failed", "unsupported")}
    write_json(out / "summary.json", summary)
    print(json.dumps({"output": str(out), **summary}, ensure_ascii=False))
    return int(summary["failed"] != 0)


if __name__ == "__main__":
    sys.exit(main())
