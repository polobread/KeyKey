#!/usr/bin/env python3
"""Explicit migration-only comparison of phase-two sessions with macOS observations."""
import argparse
import ctypes as c
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
METHODS = {"traditional", "cangjie", "simplex"}


class Api:
    def __init__(self, library):
        self.lib = c.CDLL(str(library))
        ptr, size = c.c_void_p, c.c_size_t
        declarations = {
            "guanyinma_session_open": [ptr, size, ptr, size, c.POINTER(ptr)],
            "guanyinma_session_apply": [ptr, ptr, size, c.POINTER(ptr)],
            "guanyinma_session_snapshot": [ptr, c.POINTER(ptr)],
            "guanyinma_session_close": [c.POINTER(ptr)],
            "guanyinma_result_close": [c.POINTER(ptr)],
            "guanyinma_result_json": [ptr, ptr, size, c.POINTER(size)],
            "guanyinma_last_error": [ptr, size, c.POINTER(size)],
        }
        for name, arguments in declarations.items():
            fn = getattr(self.lib, name)
            fn.argtypes, fn.restype = arguments, c.c_int32

    @staticmethod
    def span(text):
        data = text.encode("utf-8")
        return c.create_string_buffer(data), len(data)

    def check(self, status):
        if status == 0:
            return
        required = c.c_size_t()
        self.lib.guanyinma_last_error(None, 0, c.byref(required))
        buffer = c.create_string_buffer(max(required.value, 1))
        self.lib.guanyinma_last_error(buffer, len(buffer), c.byref(required))
        raise RuntimeError(f"Guanyinma status {status}: {buffer.value.decode('utf-8')}")

    def result(self, handle):
        try:
            required = c.c_size_t()
            status = self.lib.guanyinma_result_json(handle, None, 0, c.byref(required))
            if status != 5:
                self.check(status)
                raise RuntimeError("Missing result buffer size")
            buffer = c.create_string_buffer(required.value)
            self.check(self.lib.guanyinma_result_json(handle, buffer, len(buffer), c.byref(required)))
            return json.loads(buffer.value)
        finally:
            self.check(self.lib.guanyinma_result_close(c.byref(handle)))

    def open(self, path, method):
        config = {
            "method": method, "profile": "desktop",
            "traditional_selection_keys": "12345678",
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

    def apply(self, handle, operation):
        data, count = self.span(json.dumps(operation, ensure_ascii=False))
        result = c.c_void_p()
        self.check(self.lib.guanyinma_session_apply(handle, data, count, c.byref(result)))
        return self.result(result)

    def snapshot(self, handle):
        result = c.c_void_p()
        self.check(self.lib.guanyinma_session_snapshot(handle, c.byref(result)))
        return self.result(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--reference", type=Path,
                        default=ROOT / "tests/fixtures/core-functional/pre-rust/desktop.json")
    parser.add_argument("--fixture", type=Path,
                        default=ROOT / "tests/fixtures/core-functional/migration-scenarios.tsv")
    parser.add_argument("--report", type=Path, required=True,
                        help="Write outside source fixtures; never overwrites the old baseline")
    args = parser.parse_args()
    report_path = args.report.resolve()
    fixture_directory = (ROOT / "tests/fixtures/core-functional").resolve()
    if (report_path == fixture_directory or fixture_directory in report_path.parents
            or report_path in {args.reference.resolve(), args.fixture.resolve(), args.library.resolve()}):
        parser.error("--report must not overwrite migration references or the library")
    model = ROOT / "Source/Distributions/Takao/CookedDatabase/KeyKey.db"
    if report_path == model.resolve():
        parser.error("--report must not overwrite the shared model")
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
    expected = {(r["case"], r["step"]): r for r in reference["observations"][0]}
    api = Api(args.library.resolve())
    report = {"purpose": "manual phase-two migration review, macOS source authority",
              "reference": str(args.reference), "compared_cases": 0,
              "compared_snapshots": 0, "skipped_cases": {}, "differences": []}
    for name, rows in cases.items():
        reason = None
        if rows[0][2] not in METHODS or any(r[3] == "METHOD" and r[4] not in METHODS for r in rows):
            reason = "Smart Mandarin state machine belongs to phase three"
        elif any(r[3] in ("REOPEN", "RESET_LEARNING") or
                 (r[3] == "OPTION" and r[4].startswith("dynamic=")) for r in rows):
            reason = "Learning/persistence scenario belongs to phase four"
        if reason:
            report["skipped_cases"][name] = reason
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
                elif operation == "SELECT":
                    index = snapshot["candidates"].index(argument)
                    page, local = divmod(index, snapshot["page_size"])
                    if page != snapshot["page"]:
                        apply({"type": "page", "delta": page - snapshot["page"]})
                    apply({"type": "select", "index": local})
                elif operation == "METHOD":
                    apply({"type": "set_method", "method": argument})
                    config["method"] = argument
                elif operation == "OPTION":
                    key, value = argument.split("=", 1)
                    if key == "layout":
                        apply({"type": "set_layout", "layout": value})
                    else:
                        method = snapshot["method"]
                        options = config[method]
                        key = {"clear_on_error": "clear_on_error"}.get(key, key)
                        options[key] = ({"0": "original", "1": "mixed", "2": "half"}[value]
                                        if key == "punctuation" else value == "true")
                        apply({"type": "set_table_options", "method": method, "options": options})
                else:
                    raise ValueError(f"Unsupported phase-two operation: {operation}")
                before = expected[(name, step)]
                actual = {"committed": committed, "composition": snapshot["composition"],
                          "reading": snapshot["reading"], "candidates": snapshot["candidates"],
                          "page": snapshot["page"], "highlight": snapshot["highlight"] or 0}
                fields = [key for key in actual if actual[key] != before[key]]
                # Legacy panel page-size remains stale when hidden; only compare visible pages.
                if actual["candidates"] and snapshot["page_size"] != before["page_size"]:
                    fields.append("page_size")
                if fields:
                    report["differences"].append({
                        "case": name, "step": step, "operation": operation, "argument": argument,
                        "fields": fields, "expected": {key: before[key] for key in fields},
                        "actual": {key: snapshot["page_size"] if key == "page_size" else actual[key]
                                   for key in fields},
                    })
                report["compared_snapshots"] += 1
            report["compared_cases"] += 1
        finally:
            api.check(api.lib.guanyinma_session_close(c.byref(handle)))
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"{report['compared_cases']} cases / {report['compared_snapshots']} snapshots, "
          f"{len(report['differences'])} changed checkpoints; "
          f"{len(report['skipped_cases'])} later-phase cases explicitly skipped")
    for difference in report["differences"][:20]:
        print(difference["case"], difference["step"], difference["fields"])
    return 1 if report["differences"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
