#!/usr/bin/env python3
"""Explicit phase-four migration review; never a daily, CI or release test."""
import argparse
import copy
from contextlib import closing
import ctypes as c
import hashlib
import json
from pathlib import Path
import sqlite3
import sys

sys.dont_write_bytecode = True
from compare_migration_phase2 import Api, ROOT


def configuration(method, user_database):
    # The controlled native recorder enables dynamic frequency for both table
    # methods unless a scenario overrides it; these are not product defaults.
    return {
        "method": method,
        "profile": "desktop",
        "traditional_selection_keys": "12345678",
        "user_database": str(user_database),
        "learning": {
            "user_phrases": True, "candidate_overrides": True,
            "bigrams": True, "table_learning": True,
        },
        "smart": {
            "candidate_selection_keys": "12345678",
            "space_opens_candidates": False,
            "candidate_cursor_at_end": False,
            "max_completed_syllables": 10,
        },
        "cangjie": {
            "realtime": False, "prefix": False, "clear_on_error": True,
            "query_at_maximum": False, "learn_selection": True,
            "punctuation": "original",
        },
        "simplex": {
            "realtime": False, "prefix": False, "clear_on_error": True,
            "query_at_maximum": True, "learn_selection": True,
            "punctuation": "original",
        },
    }


class PhaseFourApi(Api):
    def open_configuration(self, model, config):
        path, path_length = self.span(str(model))
        data, data_length = self.span(json.dumps(config))
        handle = c.c_void_p()
        self.check(self.lib.guanyinma_session_open(
            path, path_length, data, data_length, c.byref(handle)))
        return handle


def learning_rows(database, method):
    # Only the harness-created DB in an empty scratch directory is opened.
    with closing(sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True)) as db:
        rows = {
            "overrides": db.execute(
                "SELECT qstring,current FROM user_candidate_override_cache "
                "ORDER BY qstring,current").fetchall(),
            "bigrams": db.execute(
                "SELECT qstring,previous,current,probability FROM user_bigram_cache "
                "ORDER BY qstring,previous,current").fetchall(),
            "unigrams": db.execute(
                "SELECT qstring,current,probability,backoff FROM user_unigrams "
                "ORDER BY qstring,current").fetchall(),
            "table": db.execute(
                "SELECT code,current,count FROM table_learning WHERE method=? "
                "ORDER BY code,current", (method,)).fetchall(),
        }
    return {group: [list(row) for row in values] for group, values in rows.items()}


def compare_learning(expected, actual):
    differences, notes = [], []
    numeric = {"bigrams": {3}, "unigrams": {2, 3}, "table": {2}}
    for group in ("overrides", "bigrams", "unigrams", "table"):
        old, new = expected[group], actual[group]
        if len(old) != len(new):
            differences.append(group)
            continue
        for row_number, (before, after) in enumerate(zip(old, new)):
            if len(before) != len(after):
                differences.append(group)
                continue
            for column, (left, right) in enumerate(zip(before, after)):
                if column not in numeric.get(group, set()):
                    equal = left == right
                elif group == "table":
                    equal = int(left) == int(right)
                else:
                    a, b = float(left), float(right)
                    equal = a == b
                    if not equal and abs(a - b) <= 0.0000005 + 1e-12:
                        # Legacy cache saves interpolate %f (six decimals).
                        # Preserve and report this difference, rather than
                        # changing Rust's full-precision storage to hide it.
                        notes.append({
                            "group": group, "row": row_number, "column": column,
                            "native": left, "rust": right,
                            "reason": "legacy six-decimal serialization",
                        })
                        equal = True
                if not equal:
                    differences.append(group)
    return sorted(set(differences)), notes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--scratch", "--scratch-empty", dest="scratch",
                        type=Path, required=True,
                        help="New or empty directory for isolated user stores; never a real profile")
    parser.add_argument("--reference", type=Path,
                        default=ROOT / "tests/fixtures/core-functional/pre-rust/desktop.json")
    parser.add_argument("--fixture", type=Path,
                        default=ROOT / "tests/fixtures/core-functional/migration-scenarios.tsv")
    args = parser.parse_args()
    model = ROOT / "Source/Distributions/Takao/CookedDatabase/KeyKey.db"
    protected = (ROOT / "tests/fixtures/core-functional").resolve()
    report, scratch = args.report.resolve(), args.scratch.resolve()
    protected_files = {model.resolve(), args.library.resolve(),
                       args.reference.resolve(), args.fixture.resolve()}
    for output in (report, scratch):
        if output == protected or protected in output.parents or output in protected_files:
            parser.error("outputs must not overwrite migration references, the model or the library")
    if report == scratch:
        parser.error("--report must be a file distinct from the scratch directory")
    if report.is_file():
        with report.open("rb") as stream:
            if stream.read(16) == b"SQLite format 3" + bytes([0]):
                parser.error("--report must not overwrite a SQLite database")
    if scratch.exists() and (not scratch.is_dir() or any(scratch.iterdir())):
        parser.error("--scratch must be empty or not exist; no files will be removed")
    reference = json.loads(args.reference.read_text())
    if reference["backend"] != "desktop":
        parser.error("macOS desktop is the authoritative migration reference")
    if hashlib.sha256(model.read_bytes()).hexdigest() != reference["model_sha256"]:
        parser.error("model differs from the reference; isolate engine and model changes")
    if hashlib.sha256(args.fixture.read_bytes()).hexdigest() != reference["fixture_sha256"]:
        parser.error("scenario corpus differs from the reference")
    expected = {(row["case"], row["step"]): row
                for row in reference["observations"][0]}
    cases = {}
    for line in args.fixture.read_text().splitlines():
        if line and not line.startswith("#"):
            row = line.split("\t")
            if row[1] == "hardware":
                cases.setdefault(row[0], []).append(row)
    api = PhaseFourApi(args.library.resolve())
    scratch.mkdir(parents=True, exist_ok=True)
    result = {
        "purpose": "explicit manual phase-four migration comparison",
        "reference": str(args.reference.resolve()),
        "scratch": str(scratch), "compared_cases": 0, "compared_snapshots": 0,
        "differences": [], "numeric_serialization_notes": [],
    }
    for case_number, (name, rows) in enumerate(cases.items(), 1):
        case_directory = scratch / f"case-{case_number:04d}"
        case_directory.mkdir()
        user_database = case_directory / "user.db"
        config = configuration(rows[0][2], user_database)
        handle = api.open_configuration(model, config)
        snapshot, committed = api.snapshot(handle), ""
        try:
            for step, row in enumerate(rows, 1):
                operation, argument = row[3:5]

                def apply(value):
                    nonlocal snapshot, committed
                    snapshot = api.apply(handle, value)
                    committed += snapshot["effects"]["commit"]

                if operation == "TYPE":
                    for character in argument:
                        apply({"type": "character", "text": character})
                elif operation == "KEY":
                    apply({"type": "key", "key": argument.lower()})
                elif operation == "OPEN":
                    apply({"type": "open_candidates", "index": int(argument)})
                elif operation == "SELECT":
                    index = snapshot["candidates"].index(argument)
                    target_page, local = divmod(index, snapshot["page_size"])
                    if target_page != snapshot["page"]:
                        apply({"type": "page", "delta": target_page - snapshot["page"]})
                    apply({"type": "select", "index": local})
                elif operation == "METHOD":
                    apply({"type": "set_method", "method": argument})
                    config["method"] = argument
                elif operation == "OPTION":
                    key, value = argument.split("=", 1)
                    if key == "layout":
                        apply({"type": "set_layout", "layout": value})
                        config["layout"] = value
                    elif key == "space_selects":
                        apply({"type": "finish"})
                        config["smart"]["space_opens_candidates"] = value == "true"
                        apply({"type": "set_smart_options", "options": config["smart"]})
                    else:
                        method = snapshot["method"]
                        options = config[method]
                        key = {"dynamic": "learn_selection"}.get(key, key)
                        options[key] = (
                            {"0": "original", "1": "mixed", "2": "half"}[value]
                            if key == "punctuation" else value == "true")
                        apply({"type": "set_table_options", "method": method, "options": options})
                elif operation == "REOPEN":
                    if snapshot["visible_text"]:
                        raise ValueError("REOPEN requires empty composition")
                    apply({"type": "save_learning"})
                    api.check(api.lib.guanyinma_session_close(c.byref(handle)))
                    handle = api.open_configuration(model, copy.deepcopy(config))
                    snapshot = api.snapshot(handle)
                elif operation == "RESET_LEARNING":
                    if snapshot["visible_text"]:
                        raise ValueError("RESET_LEARNING requires empty composition")
                    apply({"type": "reset_learning"})
                else:
                    raise ValueError(f"unsupported migration operation: {operation}")
                old = expected[(name, step)]
                actual = {
                    "committed": committed, "composition": snapshot["visible_text"],
                    "reading": snapshot["reading"], "candidates": snapshot["candidates"],
                    "page": snapshot["page"], "highlight": snapshot["highlight"] or 0,
                }
                if snapshot["method"] == "smart":
                    actual["cursor"] = snapshot["cursor"]
                fields = [field for field in actual if actual[field] != old[field]]
                if actual["candidates"] and snapshot["page_size"] != old["page_size"]:
                    fields.append("page_size")
                current_learning = learning_rows(user_database, snapshot["method"])
                learning_fields, notes = compare_learning(old["learning"], current_learning)
                fields += ["learning." + field for field in learning_fields]
                for note in notes:
                    result["numeric_serialization_notes"].append({
                        "case": name, "step": step, **note})
                if fields:
                    result["differences"].append({
                        "case": name, "step": step, "operation": operation,
                        "argument": argument, "fields": fields,
                        "expected": {field: old["learning"][field[9:]]
                                     if field.startswith("learning.") else old[field]
                                     for field in fields},
                        "actual": {field: current_learning[field[9:]]
                                   if field.startswith("learning.") else
                                   snapshot["page_size"] if field == "page_size" else actual[field]
                                   for field in fields},
                    })
                result["compared_snapshots"] += 1
            result["compared_cases"] += 1
        finally:
            if handle:
                api.check(api.lib.guanyinma_session_close(c.byref(handle)))
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(f"{result['compared_cases']} cases / {result['compared_snapshots']} snapshots, "
          f"{len(result['differences'])} changed checkpoints; "
          f"{len(result['numeric_serialization_notes'])} legacy numeric serialization notes")
    for difference in result["differences"][:20]:
        print(difference["case"], difference["step"], difference["fields"])
    return 1 if result["differences"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
