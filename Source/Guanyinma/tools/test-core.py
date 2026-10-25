#!/usr/bin/env python3
"""Run the shared core's Rust and C ABI contracts without a frontend or UI.

A non-host target needs an explicit Cargo runner. --build-only never reports
executed tests or a passing runtime result. Mobile runners may stage the model
and libraries, but must execute the original test binaries and propagate errors.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import time

CORE = Path(__file__).resolve().parents[1]
CANONICAL_MODEL = CORE.parent / "Distributions/Takao/CookedDatabase/KeyKey.db"
SUMMARY = re.compile(
    r"test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored; "
    r"(\d+) measured; (\d+) filtered out"
)


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def argv_json(value, name):
    if value is None:
        return []
    try:
        result = json.loads(value)
    except json.JSONDecodeError as error:
        raise ValueError(f"{name} must be a JSON argv array: {error}") from error
    if not isinstance(result, list) or not result or any(
        not isinstance(item, str) or not item or "\0" in item for item in result
    ):
        raise ValueError(f"{name} must be a nonempty JSON array of nonempty strings")
    return result


def run_step(report, name, command, env, timeout, *, check=True):
    print(f"Guanyinma core: {name}", flush=True)
    started = time.monotonic()
    step = {"name": name, "command": command, "returncode": None}
    report["steps"].append(step)
    try:
        result = subprocess.run(
            command, cwd=CORE, env=env, check=False,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding="utf-8", errors="replace", timeout=timeout,
        )
        step.update(returncode=result.returncode, output=result.stdout)
    except (OSError, subprocess.TimeoutExpired) as error:
        step["error"] = str(error)
        raise
    finally:
        step["elapsed_seconds"] = round(time.monotonic() - started, 6)
    if check and result.returncode:
        print(result.stdout, end="", flush=True)
        raise RuntimeError(f"{name} failed with exit {result.returncode}")
    return result.stdout


def rust_results(output):
    totals = dict(passed=0, failed=0, ignored=0, measured=0, filtered_out=0)
    summaries = []
    for match in SUMMARY.finditer(output):
        item = {"result": match.group(1)}
        for key, value in zip(totals, match.groups()[1:]):
            item[key] = int(value)
            totals[key] += int(value)
        summaries.append(item)
    binaries = []
    for line in output.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(message, dict):
            continue
        if message.get("reason") == "compiler-artifact" and message.get("executable"):
            if message.get("profile", {}).get("test"):
                binaries.append({"name": message["target"]["name"],
                                 "path": message["executable"]})
    return {**totals, "summaries": summaries}, binaries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cargo", default=os.environ.get("CARGO", "cargo"),
                        help="Cargo executable path, not a shell command")
    parser.add_argument("--sqlite-provider", choices=("system", "bundled"), default="system")
    parser.add_argument("--profile", choices=("debug", "release"), default="release")
    parser.add_argument("--release", dest="profile", action="store_const", const="release")
    parser.add_argument("--target", help="Cargo target triple; defaults to CARGO_BUILD_TARGET or host")
    parser.add_argument("--runner-json", help="target executable runner prefix as a JSON argv array")
    parser.add_argument("--cc-json", help="C compiler command as a JSON argv array")
    parser.add_argument("--model", type=Path, help="host-side readonly model to use/stage")
    parser.add_argument("--report", type=Path, default=CORE / "target/core-test-results.json")
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--skip-c-abi", action="store_true", help="report C consumer as skipped explicitly")
    parser.add_argument("--timeout-seconds", type=float, default=1200)
    args = parser.parse_args()
    started = time.monotonic()
    report = {
        "schema_version": 1, "kind": "guanyinma_core", "status": "failed",
        "executed": False, "execution_attempted": False, "ui_required": False,
        "platform": {"sys_platform": sys.platform, "machine": platform.machine()},
        "host": None, "target": args.target or os.environ.get("CARGO_BUILD_TARGET"),
        "profile": args.profile, "sqlite_provider": args.sqlite_provider,
        "runner": [], "steps": [], "rust_tests": None, "test_binaries": [],
        "scope": {"rust": True, "c_abi": not args.skip_c_abi},
        "c_abi": {"status": "not_run"}, "model": {}, "canonical_model": {},
        "migration_baseline_used": False, "error": None,
    }
    write_failed = False
    model = None
    model_before = canonical_before = None
    try:
        if args.timeout_seconds <= 0:
            raise ValueError("--timeout-seconds must be positive")
        runner = argv_json(args.runner_json, "--runner-json")
        compiler = argv_json(args.cc_json, "--cc-json")
        report["runner"] = runner
        source = args.model if args.model is not None else os.environ.get("GUANYINMA_TEST_MODEL_PATH")
        if source == "":
            raise ValueError("GUANYINMA_TEST_MODEL_PATH must not be empty")
        model = (Path(source) if source is not None else CANONICAL_MODEL).resolve()
        model_before = digest(model)
        report["model"] = {"path": str(model), "sha256_before": model_before}
        canonical_before = digest(CANONICAL_MODEL)
        report["canonical_model"] = {"path": str(CANONICAL_MODEL.resolve()),
                                      "sha256_before": canonical_before}
        env = os.environ.copy()
        env.update(GUANYINMA_TEST_MODEL_PATH=str(model), CARGO_TERM_COLOR="never")
        version = run_step(report, "cargo_version", [args.cargo, "--version", "--verbose"],
                           env, args.timeout_seconds)
        host = re.search(r"^host:\s*(\S+)\s*$", version, re.MULTILINE)
        if not host:
            raise RuntimeError("Cargo did not report its host target")
        report["host"] = host.group(1)
        target = report["target"] or report["host"]
        report["target"] = target
        cross = target != report["host"]
        if cross and not runner and not args.build_only:
            raise ValueError("Cross-target runtime tests require --runner-json; "
                             "use --build-only to report compilation without execution")
        cargo = [args.cargo]
        if runner:
            cargo += ["--config", f"target.{json.dumps(target)}.runner={json.dumps(runner)}"]
        command = cargo + ["test", "--locked", "--all-targets",
                           "--message-format=json-render-diagnostics"]
        if args.offline:
            command += ["--offline"]
        if args.profile == "release":
            command += ["--release"]
        if args.sqlite_provider == "bundled":
            command += ["--features", "bundled-sqlite"]
        if args.target:
            command += ["--target", args.target]
        if args.build_only:
            command += ["--no-run"]
        report["execution_attempted"] = not args.build_only
        output = run_step(report, "rust_build" if args.build_only else "rust_tests",
                          command, env, args.timeout_seconds, check=False)
        results, binaries = rust_results(output)
        report["test_binaries"] = binaries
        if not args.build_only and results["summaries"]:
            report["rust_tests"] = {**results, "executed": True}
            report["executed"] = True
        if report["steps"][-1]["returncode"]:
            print(output, end="", flush=True)
            raise RuntimeError(f"Rust command failed with exit {report['steps'][-1]['returncode']}")
        if not binaries:
            raise RuntimeError("Cargo produced no test executables")
        if args.build_only:
            report["rust_tests"] = {"executed": False, "passed": None, "failed": None}
        else:
            report["rust_tests"] = {**results, "executed": True}
            if not results["summaries"] or results["passed"] == 0 or results["failed"]:
                raise RuntimeError("No successful Rust runtime test summary, or tests failed")
            report["executed"] = True
            print(f"Rust contracts: {results['passed']} passed, {results['failed']} failed.", flush=True)
        if args.skip_c_abi:
            report["c_abi"] = {"status": "skipped", "executed": False,
                               "reason": "explicit --skip-c-abi"}
        else:
            c_report = args.report.resolve().with_name(args.report.stem + "-c-abi.json")
            command = [sys.executable, str(CORE / "tests/run_c_abi_test.py"),
                       "--cargo", args.cargo, "--report", str(c_report)]
            if args.offline:
                command += ["--offline"]
            if args.profile == "release":
                command += ["--release"]
            if args.sqlite_provider == "bundled":
                command += ["--bundled-sqlite"]
            if args.target:
                command += ["--target", args.target]
            if runner:
                command += ["--runner-json", json.dumps(runner)]
            if compiler:
                command += ["--cc-json", json.dumps(compiler)]
            if args.build_only:
                command += ["--build-only"]
            try:
                run_step(report, "c_abi_build" if args.build_only else "c_abi_tests",
                         command, env, args.timeout_seconds)
            finally:
                if c_report.is_file():
                    report["c_abi"] = json.loads(c_report.read_text(encoding="utf-8"))
                    report["c_abi_report_path"] = str(c_report)
            expected = "built_not_executed" if args.build_only else "passed"
            if report["c_abi"].get("status") != expected:
                raise RuntimeError(f"C consumer did not report {expected}")
            if not args.build_only and not report["c_abi"].get("executed"):
                raise RuntimeError("C consumer did not execute")
        report["status"] = "built_not_executed" if args.build_only else "passed"
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        report.update(status="failed", error=str(error))
    finally:
        for path, before, key in ((model, model_before, "model"),
                                  (CANONICAL_MODEL, canonical_before, "canonical_model")):
            if path is None or before is None:
                continue
            try:
                after = digest(path)
                report[key].update(sha256_after=after, unchanged=after == before)
                if after != before:
                    report.update(status="failed", error=f"Readonly model changed: {path}")
            except OSError as error:
                report.update(status="failed", error=str(error))
        report["elapsed_seconds"] = round(time.monotonic() - started, 6)
        try:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                                   encoding="utf-8")
        except OSError as error:
            print(f"Could not write core report: {error}", file=sys.stderr)
            write_failed = True
    if write_failed:
        return 1
    print(f"Core result: {report['status']}; report: {args.report}", flush=True)
    if report["error"]:
        print(report["error"], file=sys.stderr)
    return 0 if report["status"] in {"passed", "built_not_executed"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
