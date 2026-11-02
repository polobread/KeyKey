#!/usr/bin/env python3
"""Compile and run a native C consumer; unrelated to migration baselines or UI."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import subprocess
import sys
import tempfile
import time

CORE = Path(__file__).resolve().parents[1]
REPOSITORY = CORE.parent.parent
DEFAULT_MODEL = REPOSITORY / "Source/Distributions/Takao/CookedDatabase/KeyKey.db"
WINDOWS = sys.platform == "win32"


def command_prefix(value):
    if Path(value).is_file():
        return [value]
    words = shlex.split(value, posix=not WINDOWS)
    if WINDOWS:
        words = [word[1:-1] if word.startswith('"') and word.endswith('"') else word
                 for word in words]
    if not words:
        raise RuntimeError("compiler/Cargo command must not be empty")
    return words


def json_command(value, description):
    words = json.loads(value)
    if not isinstance(words, list) or any(not isinstance(word, str) or not word for word in words):
        raise RuntimeError(description + " must be a JSON array of nonempty argument strings")
    return words


def run_step(report, name, command, display=True, **kwargs):
    step = {"name": name, "command": command, "returncode": None,
            "stdout": "", "stderr": ""}
    report["steps"].append(step)
    started = time.monotonic()
    try:
        result = subprocess.run(command, cwd=CORE, capture_output=True,
                                encoding="utf-8", errors="replace", **kwargs)
        step.update(returncode=result.returncode, stdout=result.stdout, stderr=result.stderr)
        if display and result.stdout:
            print(result.stdout, end="", flush=True)
        if display and result.stderr:
            print(result.stderr, end="", file=sys.stderr, flush=True)
        if result.returncode:
            raise RuntimeError(f"{name} failed with exit code {result.returncode}")
        return result
    except OSError as error:
        step["stderr"] = str(error)
        raise
    finally:
        step["elapsed_seconds"] = round(time.monotonic() - started, 6)


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def compile_command(compiler, library, executable, windows_target):
    source = str(CORE / "tests/c_abi_smoke.c")
    if windows_target:
        # Run from a VS developer prompt, with cl/link and the matching SDK/CRT.
        # Link the cdylib import library, never the similarly named staticlib.
        import_library = library.with_name("guanyinma.dll.lib")
        if not import_library.is_file():
            raise RuntimeError(f"MSVC import library is missing: {import_library}")
        command = compiler + [
            "/nologo", "/std:c11", "/utf-8", "/W4", "/WX", "/TC", "/MD",
            "/I" + str(CORE / "include"), source,
            "/Fo" + str(executable.with_suffix(".obj")), "/Fe" + str(executable),
            "/link", str(import_library), "/SUBSYSTEM:CONSOLE", "/INCREMENTAL:NO",
            "/PDB:" + str(executable.with_suffix(".pdb")),
        ]
        return command, import_library
    return compiler + [
        "-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic",
        "-I", str(CORE / "include"), source, "-L", str(library.parent), "-lguanyinma",
        "-Xlinker", "-rpath", "-Xlinker", str(library.parent),
        "-o", str(executable),
    ], None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cargo", default=os.environ.get("CARGO", "cargo"))
    parser.add_argument("--cc", default=os.environ.get("CC", "cl" if WINDOWS else "cc"),
                        help="native C compiler command (Windows: MSVC cl or compatible clang-cl)")
    parser.add_argument("--cc-json", help="compiler prefix as a JSON argv array; overrides --cc/CC")
    parser.add_argument("--target", help="Cargo target triple; defaults to CARGO_BUILD_TARGET or the host")
    parser.add_argument("--runner-json", help="native/device runner prefix as a JSON argv array")
    parser.add_argument("--build-only", action="store_true", help="compile C consumer without claiming execution")
    parser.add_argument("--bundled-sqlite", action="store_true")
    parser.add_argument("--release", action="store_true")
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--report", type=Path, help="write a UTF-8 JSON result, including failures")
    args = parser.parse_args()
    started = time.monotonic()
    model_path = os.environ.get("GUANYINMA_TEST_MODEL_PATH", str(DEFAULT_MODEL))
    model = None
    report = {
        "schema_version": 1, "kind": "guanyinma_c_abi", "status": "failed",
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "platform": {"sys_platform": sys.platform, "machine": platform.machine()},
        "profile": "release" if args.release else "debug",
        "sqlite_provider": "bundled" if args.bundled_sqlite else "system",
        "target": args.target or os.environ.get("CARGO_BUILD_TARGET"),
        "runner": [], "execution_attempted": False, "executed": False,
        "checks": None, "compiler": None, "library": None, "executable": None,
        "model": {"path": model_path, "sha256_before": None,
                  "sha256_after": None, "unchanged": None},
        "unicode_user_database": None, "steps": [], "error": "verification did not complete",
    }
    try:
        if not model_path:
            raise RuntimeError("GUANYINMA_TEST_MODEL_PATH must not be empty")
        model = Path(model_path).resolve()
        report["model"]["path"] = str(model)
        cargo = command_prefix(args.cargo)
        compiler = (json_command(args.cc_json, "--cc-json") if args.cc_json
                    else command_prefix(args.cc))
        if not compiler:
            raise RuntimeError("C compiler prefix must not be empty")
        runner = json_command(args.runner_json, "--runner-json") if args.runner_json else []
        report["runner"] = runner
        report["compiler"] = compiler
        offline = ["--offline"] if args.offline else []
        build = cargo + ["build", "--locked", *offline]
        if args.bundled_sqlite:
            build += ["--features", "bundled-sqlite"]
        if args.release:
            build += ["--release"]
        if args.target:
            build += ["--target", args.target]
        report["model"]["sha256_before"] = digest(model)
        run_step(report, "cargo_build", build)
        # Metadata honors CARGO_TARGET_DIR. Cross targets execute only through
        # the caller's native/device runner, or explicitly remain build-only.
        metadata = json.loads(run_step(report, "cargo_metadata", cargo + [
            "metadata", "--locked", "--no-deps", "--format-version", "1", *offline,
        ], display=False).stdout)
        directory = Path(metadata["target_directory"])
        target = report["target"]
        if target:
            directory /= Path(target).stem if target.endswith(".json") else target
        directory /= report["profile"]
        windows_target = "windows-msvc" in target if target else WINDOWS
        apple_target = ("apple" in target) if target else sys.platform == "darwin"
        library_name = ("guanyinma.dll" if windows_target else "libguanyinma.dylib"
                        if apple_target else "libguanyinma.so")
        library = directory / library_name
        report["library"] = {"path": str(library), "sha256": digest(library)}
        with tempfile.TemporaryDirectory(prefix="guanyinma-c-abi-") as temporary:
            executable = Path(temporary) / ("c-abi-smoke.exe" if windows_target else "c-abi-smoke")
            # POSIX also exercises JSON path escaping; Windows supplies real
            # backslash separators. Both execute with non-ASCII argv and DB names.
            filename = "使用者 資料.db" if WINDOWS else '使用者 "資料"\\路徑.db'
            user_database = Path(temporary) / filename
            report["unicode_user_database"] = {
                "path": str(user_database), "non_ascii": True, "created": False,
            }
            command, import_library = compile_command(compiler, library, executable, windows_target)
            if import_library:
                report["library"]["import_library"] = {
                    "path": str(import_library), "sha256": digest(import_library),
                }
            run_step(report, "compile_c_consumer", command)
            report["executable"] = {"path": str(executable), "sha256": digest(executable)}
            environment = os.environ.copy()
            environment.update(
                GUANYINMA_TEST_NATIVE_LIBRARY_DIR=str(library.parent),
                GUANYINMA_TEST_MODEL_PATH=str(model),
                GUANYINMA_TEST_USER_DATABASE_PATH=str(user_database),
            )
            if windows_target:
                # The consumer and its Rust cdylib remain separate artifacts.
                environment["PATH"] = str(library.parent) + os.pathsep + environment.get("PATH", "")
            if args.build_only:
                report.update(status="built_not_executed", error=None)
            else:
                report["execution_attempted"] = True
                # A native/device runner may ad-hoc sign these artifacts (iOS).
                # Preserve the compiled digest and report the actual bytes after
                # execution, including runner failures after signing.
                for artifact in (report["library"], report["executable"]):
                    artifact["sha256_before_runner"] = artifact["sha256"]
                try:
                    result = run_step(report, "run_c_consumer", runner + [
                        str(executable), str(model), str(user_database),
                    ], env=environment)
                finally:
                    for artifact in (report["library"], report["executable"]):
                        artifact["sha256"] = digest(Path(artifact["path"]))
                matched = re.search(r"Guanyinma C ABI consumer: ([0-9]+) checks passed", result.stdout)
                if not matched:
                    raise RuntimeError("C consumer exited without its check-count result")
                report["checks"] = int(matched.group(1))
                report["executed"] = True
                # Remote runners must retrieve the actual Unicode DB (and any
                # WAL/SHM) to this path; missing files cannot count as a pass.
                created = user_database.is_file() and user_database.stat().st_size > 0
                report["unicode_user_database"]["created"] = created
                if not created:
                    raise RuntimeError("C consumer/runner did not return its Unicode user database")
                report.update(status="passed", error=None)
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        report["error"] = str(error)
    finally:
        try:
            if model is not None:
                after = digest(model)
                before = report["model"]["sha256_before"]
                report["model"].update(sha256_after=after, unchanged=before == after if before else None)
                if before and before != after:
                    report.update(status="failed", error="Model KeyKey.db changed during C ABI verification")
        except OSError as error:
            report.update(status="failed", error=str(error))
        report["elapsed_seconds"] = round(time.monotonic() - started, 6)
        if args.report:
            try:
                args.report.parent.mkdir(parents=True, exist_ok=True)
                args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            except OSError as error:
                report.update(status="failed", error=f"Could not write C ABI report: {error}")
    if report["status"] not in {"passed", "built_not_executed"}:
        print("C ABI verification failed:", report["error"], file=sys.stderr)
        return 1
    if report["status"] == "built_not_executed":
        print("C ABI consumer compiled; not executed. Model KeyKey.db bytes unchanged.")
    else:
        print("C ABI consumer passed; model KeyKey.db bytes unchanged.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
