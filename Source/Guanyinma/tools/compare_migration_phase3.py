#!/usr/bin/env python3
"""Explicit manual migration review of phase-three sessions against macOS observations."""
import argparse
import ctypes as c
import hashlib
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from compare_migration_phase2 import Api, ROOT


class PhaseThreeApi(Api):
    def open(self, path, method):
        config = {
            "method": method, "profile": "desktop",
            "traditional_selection_keys": "12345678",
            "smart": {"candidate_selection_keys": "12345678",
                      "space_opens_candidates": False,
                      "candidate_cursor_at_end": False,
                      "max_completed_syllables": 10},
            "cangjie": {"realtime": False, "prefix": False, "clear_on_error": True,
                        "query_at_maximum": False, "punctuation": "original"},
            "simplex": {"realtime": False, "prefix": False, "clear_on_error": True,
                        "query_at_maximum": True, "punctuation": "original"},
        }
        path, length = self.span(str(path))
        data, count = self.span(json.dumps(config))
        handle = c.c_void_p()
        self.check(self.lib.guanyinma_session_open(path, length, data, count, c.byref(handle)))
        return handle, config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--reference", type=Path,
                        default=ROOT / "tests/fixtures/core-functional/pre-rust/desktop.json")
    parser.add_argument("--fixture", type=Path,
                        default=ROOT / "tests/fixtures/core-functional/migration-scenarios.tsv")
    parser.add_argument("--report", type=Path, required=True,
                        help="Explicit output outside migration references; never refreshes baseline")
    args = parser.parse_args()
    report_path = args.report.resolve()
    model = ROOT / "Source/Distributions/Takao/CookedDatabase/KeyKey.db"
    protected = (ROOT / "tests/fixtures/core-functional").resolve()
    if (report_path == protected or protected in report_path.parents
            or report_path in {args.reference.resolve(), args.fixture.resolve(),
                               args.library.resolve(), model.resolve()}):
        parser.error("--report must not overwrite migration references, the model or the library")
    reference = json.loads(args.reference.read_text())
    if reference["backend"] != "desktop":
        raise ValueError("macOS desktop is the authoritative reference")
    if hashlib.sha256(model.read_bytes()).hexdigest() != reference["model_sha256"]:
        raise ValueError("Model changed; isolate model and engine migration")
    if hashlib.sha256(args.fixture.read_bytes()).hexdigest() != reference["fixture_sha256"]:
        raise ValueError("Scenario corpus changed")
    cases = {}
    for line in args.fixture.read_text().splitlines():
        if line and not line.startswith("#"):
            row = line.split("\t")
            if row[1] == "hardware":
                cases.setdefault(row[0], []).append(row)
    expected = {(row["case"], row["step"]): row for row in reference["observations"][0]}
    api = PhaseThreeApi(args.library.resolve())
    report = {"purpose": "manual phase-three migration review, macOS source authority",
              "reference": str(args.reference), "compared_cases": 0,
              "compared_snapshots": 0, "skipped_cases": {}, "differences": []}
    for name, rows in cases.items():
        # This scenario intentionally repeats a reading after selecting a
        # different homophone. The old engine reuses its learned preference
        # during the same session; persistent/preference learning is phase four.
        if name == "select_then_append":
            report["skipped_cases"][name] = (
                "Same-session learned candidate preference reuse belongs to phase four; "
                "the frozen native observation remains unchanged")
            continue
        if any(row[3] in ("REOPEN", "RESET_LEARNING")
               or (row[3] == "OPTION" and row[4].startswith("dynamic=")) for row in rows):
            report["skipped_cases"][name] = "Learning/persistence scenario belongs to phase four"
            continue
        handle, config = api.open(model, rows[0][2])
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
                    page, local = divmod(index, snapshot["page_size"])
                    if page != snapshot["page"]:
                        apply({"type": "page", "delta": page - snapshot["page"]})
                    apply({"type": "select", "index": local})
                elif operation == "METHOD":
                    apply({"type": "set_method", "method": argument})
                elif operation == "OPTION":
                    key, value = argument.split("=", 1)
                    if key == "layout":
                        apply({"type": "set_layout", "layout": value})
                    elif key == "space_selects":
                        # The old recorder retires the context on option changes.
                        apply({"type": "finish"})
                        config["smart"]["space_opens_candidates"] = value == "true"
                        apply({"type": "set_smart_options", "options": config["smart"]})
                    else:
                        method = snapshot["method"]
                        options = config[method]
                        options[key] = ({"0": "original", "1": "mixed", "2": "half"}[value]
                                        if key == "punctuation" else value == "true")
                        apply({"type": "set_table_options", "method": method, "options": options})
                else:
                    raise ValueError(f"Unsupported migration operation: {operation}")
                old = expected[(name, step)]
                actual = {"committed": committed, "composition": snapshot["visible_text"],
                          "reading": snapshot["reading"], "candidates": snapshot["candidates"],
                          "page": snapshot["page"], "highlight": snapshot["highlight"] or 0}
                # Smart has separate completed/unfinished buffers; its visible
                # combined cursor corresponds directly to the native snapshot.
                if snapshot["method"] == "smart":
                    actual["cursor"] = snapshot["cursor"]
                fields = [field for field in actual if actual[field] != old[field]]
                if actual["candidates"] and snapshot["page_size"] != old["page_size"]:
                    fields.append("page_size")
                if fields:
                    report["differences"].append({
                        "case": name, "step": step, "operation": operation, "argument": argument,
                        "fields": fields, "expected": {field: old[field] for field in fields},
                        "actual": {field: snapshot["page_size"] if field == "page_size"
                                   else actual[field] for field in fields},
                    })
                report["compared_snapshots"] += 1
            report["compared_cases"] += 1
        finally:
            api.check(api.lib.guanyinma_session_close(c.byref(handle)))
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"{report['compared_cases']} cases / {report['compared_snapshots']} snapshots, "
          f"{len(report['differences'])} changed checkpoints; "
          f"{len(report['skipped_cases'])} phase-four cases explicitly skipped")
    for difference in report["differences"][:20]:
        print(difference["case"], difference["step"], difference["fields"])
    return 1 if report["differences"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
