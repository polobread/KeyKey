#!/usr/bin/env python3
"""Manually capture or compare pre-Rust behavior; never a daily/release test gate."""
from __future__ import annotations

import argparse
from collections import defaultdict
from contextlib import nullcontext
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/core-functional/migration-scenarios.tsv"
BASELINES = ROOT / "tests/fixtures/core-functional/pre-rust"
MODEL = ROOT / "Source/Distributions/Takao/CookedDatabase/KeyKey.db"
BACKENDS = ("desktop", "unix", "swift", "android", "windows")
METHODS = {"smart", "traditional", "cangjie", "simplex"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def call(command: list[str], *, env: dict[str, str] | None = None,
         quiet: bool = False) -> str:
    result = subprocess.run(command, cwd=ROOT, env=env, text=True,
                            stdout=subprocess.PIPE if quiet else None,
                            stderr=subprocess.STDOUT if quiet else None)
    if result.returncode:
        if result.stdout:
            print(result.stdout, file=sys.stderr)
        raise RuntimeError(f"Command failed ({result.returncode}): {shlex.join(command)}")
    return result.stdout or ""


def compiler() -> list[str]:
    return shlex.split(os.environ.get("CXX", "c++")) + ["-std=c++17", "-O2"]


def compile_desktop(build: Path) -> Path:
    command = compiler() + [
        "-DOV_USE_SQLITE", "-DOVIMTRADITIONALMANDARIN_USE_ABSOLUTE_ORDER_QUERY_STRING",
        '-DOVIMMANDARIN_IDENTIFIER="Mandarin"',
        '-DOVIMMANDARIN_PUNCTUATIONS_TABLE_PREFIX="Punctuations"',
    ]
    for name in ("OpenVanilla", "PlainVanilla", "Formosa", "Manjusri"):
        headers = ROOT / "Source/Frameworks" / name / "Headers"
        command += ["-I", str(headers)]
        if sys.platform == "darwin":
            framework = build / (name + ".framework")
            framework.mkdir()
            (framework / "Headers").symlink_to(headers)
    if sys.platform == "darwin":
        command += ["-F", str(build)]
    for name in ("OVIMMandarin", "OVIMGeneric"):
        command += ["-I", str(ROOT / "Source/ModulePackages" / name)]
    executable = build / "desktop-migration-baseline"
    command += [
        str(ROOT / "tests/desktop_smart_functional.cpp"),
        str(ROOT / "Source/ModulePackages/OVIMMandarin/OVIMSmartMandarin.cpp"),
        str(ROOT / "Source/ModulePackages/OVIMMandarin/OVIMTraditionalMandarin.cpp"),
        str(ROOT / "Source/ModulePackages/OVIMGeneric/OVIMGeneric.cpp"),
        str(ROOT / "Source/Frameworks/Manjusri/Source/Node.cpp"),
        str(ROOT / "Source/Frameworks/Formosa/Source/Mandarin.cpp"),
        "-lsqlite3", "-o", str(executable),
    ]
    call(command, quiet=True)
    return executable


def compile_unix(build: Path) -> Path:
    engine = ROOT / "Source/Loaders/Linux-IME/engine"
    executable = build / "unix-migration-baseline"
    command = compiler() + [
        "-I", str(engine / "include"),
        str(ROOT / "Source/Loaders/Linux-IME/tests/shared_core_functional.cpp"),
        *map(str, sorted((engine / "src").glob("*.cpp"))), "-lsqlite3",
    ]
    if sys.platform == "darwin":
        command += ["-liconv"]
    call(command + ["-o", str(executable)], quiet=True)
    return executable


def mappings(values: list[str]) -> dict[str, list[Path]]:
    result: dict[str, list[Path]] = defaultdict(list)
    for value in values:
        name, separator, path = value.partition("=")
        if not separator or name not in BACKENDS or not path:
            raise ValueError(f"Expected BACKEND=TRACE_PATH, got {value!r}")
        result[name].append(Path(path).resolve())
    return result


def fixture_rows(fixture: Path, backend: str) -> list[tuple]:
    rows = []
    active = ""
    step = 0
    for line in fixture.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 5:
            raise ValueError("Migration fixture must contain five TSV columns")
        name, profile, method, operation, argument = fields
        if name != active:
            active, step = name, 0
        step += 1
        if profile == "touch" and backend in ("desktop", "unix", "windows"):
            continue
        rows.append((name, step, profile, operation, argument))
    return rows


def load_trace(path: Path, fixture: Path, backend: str) -> list[dict]:
    records = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    expected = fixture_rows(fixture, backend)
    actual = [(r["case"], r["step"], r["profile"], r["operation"], r["argument"])
              for r in records]
    if actual != expected:
        mismatch = next((i for i, pair in enumerate(zip(actual, expected))
                         if pair[0] != pair[1]), min(len(actual), len(expected)))
        raise ValueError(f"{backend}: missing/reordered operation at index {mismatch}; "
                         f"expected {len(expected)} snapshots, got {len(actual)}")
    if {r["method"] for r in records} != METHODS:
        raise ValueError(f"{backend}: trace does not cover all four input methods")
    for record in records:
        required = {"committed", "composition", "reading", "cursor", "cursor_unit",
                    "candidates", "page", "page_size", "highlight", "learning"}
        if required - record.keys():
            raise ValueError(f"{backend}: missing snapshot fields {required - record.keys()}")
        if not isinstance(record["candidates"], list) or not all(
                isinstance(value, str) for value in record["candidates"]):
            raise ValueError(f"{backend}: candidate order must be a string array")
        learning = record["learning"]
        if not isinstance(learning, dict) or set(learning) != {"overrides", "bigrams", "unigrams", "table"}:
            raise ValueError(f"{backend}: learning must expose all four normalized row groups")
        for group, width in (("overrides", 2), ("bigrams", 4), ("unigrams", 4), ("table", 3)):
            if not isinstance(learning[group], list) or not all(
                    isinstance(row, list) and len(row) == width and all(isinstance(v, str) for v in row)
                    for row in learning[group]):
                raise ValueError(f"{backend}: invalid normalized learning rows in {group}")
    return records


def source_fingerprint(backend: str) -> dict[str, str]:
    common = ["Source/Shared", "Source/DataTables"]
    if backend in ("desktop", "windows"):
        directories = common + [
            "Source/Frameworks/OpenVanilla", "Source/Frameworks/PlainVanilla",
            "Source/Frameworks/Formosa", "Source/Frameworks/Manjusri",
            "Source/ModulePackages/OVIMMandarin", "Source/ModulePackages/OVIMGeneric",
        ]
        explicit = ["tests/desktop_smart_functional.cpp"]
        if backend == "windows":
            explicit += ["Source/Loaders/Windows-TSF/WindowsTableInputMethod.cpp",
                         "Source/Loaders/Windows-TSF/WindowsTableInputMethod.h"]
    elif backend == "unix":
        directories = common + ["Source/Loaders/Linux-IME/engine"]
        explicit = ["Source/Loaders/Linux-IME/tests/shared_core_functional.cpp"]
    elif backend == "swift":
        directories = common + ["Source/Loaders/iOS-Keyboard/KeyKeyEngine/Sources"]
        explicit = ["Source/Loaders/iOS-Keyboard/KeyKeyEngine/Tests/KeyKeyEngineTests/CoreFunctionalTests.swift"]
    else:
        directories = common + ["Source/Loaders/Android-IME/app/src/main/java"]
        explicit = ["Source/Loaders/Android-IME/app/src/androidTest/java/tw/chichi77/keykey/android/CoreFunctionalInstrumentedTest.java"]
    suffixes = {".cpp", ".c", ".h", ".swift", ".java", ".cin"}
    files = {ROOT / name for name in explicit}
    for directory in directories:
        files.update(p for p in (ROOT / directory).rglob("*")
                     if p.is_file() and p.suffix in suffixes)
    return {str(p.relative_to(ROOT)): sha256(p) for p in sorted(files)}


def variations(observations: list[list[dict]]) -> list[dict]:
    result = []
    first = observations[0]
    for index, state in enumerate(first):
        fields = sorted({key for sample in observations[1:]
                         for key in set(state) | set(sample[index])
                         if state.get(key) != sample[index].get(key)})
        if fields:
            result.append({"case": state["case"], "step": state["step"], "fields": fields})
    return result


def capture_package(backend: str, traces: list[list[dict]], fixture: Path,
                    environment: str) -> dict:
    distinct = []
    for trace in traces:
        if trace not in distinct:
            distinct.append(trace)
    source = call(["git", "rev-parse", "HEAD"], quiet=True).strip()
    return {
        "schema": 2, "purpose": "manual Rust migration reference; not a daily/release gate",
        "backend": backend, "source_commit": source,
        "source_files_sha256": source_fingerprint(backend),
        "model_sha256": sha256(MODEL), "fixture_sha256": sha256(fixture),
        "environment": environment, "capture_runs": len(traces),
        "case_count": len({r["case"] for r in traces[0]}),
        "snapshot_count": len(traces[0]),
        "observed_variation": variations(distinct), "observations": distinct,
    }


def compare(reference: dict, trace: list[dict]) -> list[dict]:
    """Compare each checkpoint against every observed old-engine variant; preserve order."""
    differences = []
    observations = reference["observations"]
    if not observations or len(trace) != len(observations[0]):
        raise ValueError("Snapshot count differs from the frozen reference")
    for index, actual in enumerate(trace):
        variants = [sample[index] for sample in observations]
        if actual in variants:
            continue
        expected = min(variants, key=lambda value: sum(
            value.get(key) != actual.get(key) for key in set(value) | set(actual)))
        changed = sorted(key for key in set(expected) | set(actual)
                         if expected.get(key) != actual.get(key))
        detail = {"case": actual["case"], "step": actual["step"], "fields": changed}
        if "candidates" in changed:
            left, right = expected["candidates"], actual["candidates"]
            first = next((i for i, pair in enumerate(zip(left, right))
                          if pair[0] != pair[1]), min(len(left), len(right)))
            detail["candidate_order"] = {
                "first_changed_index": first, "before_count": len(left),
                "after_count": len(right), "before": left[first:first + 5],
                "after": right[first:first + 5],
            }
        if "learning" in changed:
            detail["learning_before"] = expected["learning"]
            detail["learning_after"] = actual["learning"]
        differences.append(detail)
    return differences


def record(backend: str, fixture: Path, build: Path, count: int) -> list[Path]:
    if backend in ("android", "windows"):
        raise ValueError(f"Import {backend} traces with --trace {backend}=PATH; "
                         "see native manual recorder instructions")
    if backend == "swift" and sys.platform != "darwin":
        raise ValueError("Swift recording requires the Apple SQLite module on macOS")
    if sys.platform == "win32":
        raise ValueError("Use the native Windows opt-in recorder, then import its JSONL")
    executable = None
    if backend == "desktop":
        executable = compile_desktop(build)
    elif backend == "unix":
        executable = compile_unix(build)
    paths = []
    for sample in range(count):
        scratch = build / f"sample-{sample}"
        scratch.mkdir()
        trace = build / f"trace-{sample}.jsonl"
        if backend == "desktop":
            call([str(executable), str(MODEL), str(fixture), str(scratch), str(trace)])
        elif backend == "unix":
            call([str(executable), str(fixture), str(MODEL),
                  str(ROOT / "Source/DataTables/bpmf-ext.cin"), str(scratch), str(trace)])
        else:
            env = dict(os.environ, KEYKEY_MIGRATION_BASELINE="1",
                       KEYKEY_CORE_FUNCTIONAL_FIXTURE=str(fixture),
                       KEYKEY_MIGRATION_TRACE=str(trace),
                       KEYKEY_MIGRATION_SCRATCH=str(scratch))
            call(["bash", str(ROOT / "Source/Guanyinma/tools/test-ios-swift-package.sh"),
                  "--filter", "CoreFunctionalTests"], env=env)
        paths.append(trace)
    return paths


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--capture", action="store_true", help="Explicitly freeze current behavior")
    action.add_argument("--compare", action="store_true", help="Review a Rust/candidate trace against the frozen reference")
    parser.add_argument("--backend", action="append", choices=BACKENDS)
    parser.add_argument("--trace", action="append", default=[], metavar="BACKEND=PATH",
                        help="Import a native/Rust JSONL; repeat for old-engine observations")
    parser.add_argument("--environment", action="append", default=[], metavar="BACKEND=DESCRIPTION")
    parser.add_argument("--fixture", type=Path, default=FIXTURE)
    parser.add_argument("--baseline-dir", type=Path, default=BASELINES)
    parser.add_argument("--replace-baseline", action="store_true",
                        help="Explicitly replace existing references; review the resulting diff")
    parser.add_argument("--samples", type=int, choices=range(1, 5),
                        help="Live capture repetitions (default 2 capture, 1 compare)")
    parser.add_argument("--report", type=Path, help="Write a machine-readable migration difference report")
    args = parser.parse_args()
    imported = mappings(args.trace)
    backends = list(dict.fromkeys(args.backend or imported.keys() or
                                 (["desktop", "unix", "swift"] if sys.platform == "darwin"
                                  else ["desktop", "unix"])))
    environments = {}
    for value in args.environment:
        name, separator, description = value.partition("=")
        if name not in BACKENDS or not separator or not description:
            parser.error("Expected --environment BACKEND=DESCRIPTION")
        environments[name] = description
    fixture = args.fixture.resolve()
    if not fixture.is_file() or not MODEL.is_file():
        parser.error("Fixture and pre-generated canonical KeyKey.db must exist")
    if args.replace_baseline and not args.capture:
        parser.error("--replace-baseline only applies to an explicit --capture")
    plans = {}
    for backend in backends:
        target = args.baseline_dir / f"{backend}.json"
        if args.capture and target.exists() and not args.replace_baseline:
            parser.error(f"Reference exists: {target}; intentional replacement requires --replace-baseline")
        if args.compare and not target.is_file():
            parser.error(f"No frozen reference: {target}; missing references are never auto-created")
        if backend in imported and backend not in environments and args.capture:
            parser.error(f"Imported {backend} capture requires --environment {backend}=DESCRIPTION")
        plans[backend] = target
    report = {"purpose": "Rust migration review only", "backends": {}}
    needs_execution = any(backend not in imported for backend in plans)
    temporary = tempfile.TemporaryDirectory(prefix="keykey-rust-migration-") if needs_execution else nullcontext(None)
    with temporary as directory:
        for backend, target in plans.items():
            print(f"[{backend}] explicit migration {'capture' if args.capture else 'comparison'}", flush=True)
            paths = imported.get(backend)
            if paths is None:
                build = Path(directory) / backend
                build.mkdir()
                paths = record(backend, fixture, build, args.samples or (2 if args.capture else 1))
            traces = [load_trace(path, fixture, backend) for path in paths]
            if args.capture:
                package = capture_package(backend, traces, fixture, environments.get(
                    backend, f"{platform.system()} {platform.release()} {platform.machine()}"))
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(json.dumps(package, ensure_ascii=False, indent=2) + "\n")
                print(f"Frozen {package['case_count']} cases / {package['snapshot_count']} snapshots, "
                      f"{len(package['observed_variation'])} checkpoints varied across {len(traces)} runs")
            else:
                reference = json.loads(target.read_text())
                if reference.get("schema") != 2 or reference.get("backend") != backend:
                    raise ValueError(f"{backend}: wrong reference schema/backend")
                if reference["fixture_sha256"] != sha256(fixture):
                    raise ValueError(f"{backend}: fixture differs; do not compare mismatched scenarios")
                if reference["model_sha256"] != sha256(MODEL):
                    raise ValueError(f"{backend}: model differs; isolate model and engine changes")
                differences = [compare(reference, trace) for trace in traces]
                report["backends"][backend] = {
                    "reference": str(target), "sample_differences": differences,
                    "known_variable_checkpoints": reference["observed_variation"],
                }
                for sample, changes in enumerate(differences, 1):
                    print(f"Sample {sample}: {len(changes)} changed checkpoints")
                    for change in changes[:15]:
                        print(f"  {change['case']} step {change['step']}: {', '.join(change['fields'])}")
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    changed = any(changes for backend in report["backends"].values()
                  for changes in backend["sample_differences"])
    return 1 if changed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, KeyError, json.JSONDecodeError) as error:
        print(f"Migration reference error: {error}", file=sys.stderr)
        raise SystemExit(2)
