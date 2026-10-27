#!/usr/bin/env python3
"""Measure production Rust executable lines with the existing headless core suite.

The reference gate is native macOS/system SQLite, using the committed
Rust toolchain. LLVM tools must already be installed; this tool downloads none.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib

CORE = Path(__file__).resolve().parents[1]
ROOT = CORE.parent.parent
SOURCE = CORE / "src"
RAW_LITERAL = re.compile(r'(?:br|cr|r)(#*)"')
CHAR_LITERAL = re.compile(r"'(?:\\(?:x[0-9a-fA-F]{2}|u\{[0-9a-fA-F_]+\}|[^\r\n])|[^'\\\r\n])'")


def masked_rust(source):
    """Blank comments and literals without changing offsets or line numbers."""
    value = list(source)
    index = 0
    while index < len(source):
        start = index
        if source.startswith("//", index):
            end = source.find("\n", index)
            index = len(source) if end < 0 else end
        elif source.startswith("/*", index):
            depth, index = 1, index + 2
            while depth and index < len(source):
                if source.startswith("/*", index):
                    depth, index = depth + 1, index + 2
                elif source.startswith("*/", index):
                    depth, index = depth - 1, index + 2
                else:
                    index += 1
            if depth:
                raise ValueError("Unterminated Rust block comment")
        else:
            raw = RAW_LITERAL.match(source, index) if (
                index == 0 or not (source[index - 1].isalnum() or source[index - 1] == "_")
            ) else None
            if raw:
                marker = '"' + raw.group(1)
                end = source.find(marker, index + len(raw.group()))
                if end < 0:
                    raise ValueError("Unterminated Rust raw string")
                index = end + len(marker)
            elif source[index] == '"':
                index += 1
                while index < len(source) and source[index] != '"':
                    index += 2 if source[index] == "\\" else 1
                if index >= len(source):
                    raise ValueError("Unterminated Rust string")
                index += 1
            elif source[index] == "'":
                # An apostrophe without a closing character literal is a lifetime.
                char = CHAR_LITERAL.match(source, index)
                if char:
                    index += len(char.group())
                else:
                    index += 1
                    continue
            else:
                index += 1
                continue
        for position in range(start, index):
            if source[position] not in "\r\n":
                value[position] = " "
    return "".join(value)


def matching(mask, start):
    pairs = {"[": "]", "(": ")", "{": "}"}
    stack = [pairs[mask[start]]]
    for index in range(start + 1, len(mask)):
        char = mask[index]
        if char in pairs:
            stack.append(pairs[char])
        elif char in "])}":
            if char != stack.pop():
                raise ValueError("Mismatched Rust delimiters")
            if not stack:
                return index
    raise ValueError("Unterminated Rust delimiter")


def test_only_ranges(source):
    """Find cfg(test) items, including helpers between production methods.

    Unknown test cfg forms or unsupported item shapes fail closed instead of
    silently counting test code as production. Strings/comments cannot add braces.
    """
    mask = masked_rust(source)
    attrs = []
    for found in re.finditer(r"#\s*!?\s*\[", mask):
        opening = mask.index("[", found.start(), found.end())
        end = matching(mask, opening) + 1
        attrs.append((found.start(), end, re.sub(r"\s+", "", mask[opening + 1:end - 1])))
    ranges = []
    for position, (start, end, attr) in enumerate(attrs):
        if attr not in ("cfg(test)", "test"):
            if re.match(r"cfg(?:_attr)?\(", attr) and re.search(r"\btest\b", attr):
                raise ValueError("Unsupported test cfg expression: " + attr)
            continue
        # Include other attributes on this same item (e.g. derive before cfg).
        first = position
        while first and not mask[attrs[first - 1][1]:attrs[first][0]].strip():
            first -= 1
        start = attrs[first][0]
        last = position
        while last + 1 < len(attrs) and not mask[end:attrs[last + 1][0]].strip():
            last += 1
            end = attrs[last][1]
        index, angles = end, 0
        while index < len(mask):
            char = mask[index]
            if char in "([":
                index = matching(mask, index) + 1
                continue
            if char == "<":
                angles += 1
            elif char == ">" and angles:
                angles -= 1
            if char == "{":
                if angles:
                    raise ValueError("Unsupported test-only generic const body")
                end = matching(mask, index) + 1
                break
            if char == ";":
                end = index + 1
                break
            if char in "},":
                raise ValueError("Unsupported test-only item shape")
            index += 1
        else:
            raise ValueError("Unterminated test-only item")
        span = (source.count("\n", 0, start) + 1, source.count("\n", 0, end - 1) + 1)
        # A mixed production/test item on one line cannot be excluded safely.
        line_start = source.rfind("\n", 0, start) + 1
        line_end = source.find("\n", end)
        if mask[line_start:start].strip() or mask[end:len(mask) if line_end < 0 else line_end].strip():
            raise ValueError("Test-only item shares a line with production code")
        ranges.append(span)
    return sorted(set(ranges))


def production_lines(lcov, source_text):
    """Merge repeated objects by source/line, retaining production DA records."""
    ranges = {path: test_only_ranges(text) for path, text in source_text.items()}
    records = {path: {} for path in source_text}
    current = None
    for line in lcov.splitlines():
        if line.startswith("SF:"):
            path = Path(line[3:]).resolve()
            current = path if path in records else None
        elif current is not None and line.startswith("DA:"):
            number, count, *_ = line[3:].split(",")
            number, count = int(number), int(count)
            if number <= 0 or number > len(source_text[current].splitlines()) or count < 0:
                raise ValueError("Invalid LCOV line record")
            if not any(first <= number <= last for first, last in ranges[current]):
                records[current][number] = max(records[current].get(number, 0), count)
        elif line == "end_of_record":
            current = None
    return records, ranges


def meets_floor(covered, executable, minimum):
    if not math.isfinite(minimum) or not 0 <= minimum <= 100:
        raise ValueError("Coverage floor must be between 0 and 100")
    if executable <= 0 or not 0 <= covered <= executable:
        raise ValueError("Coverage requires a nonempty executable-line denominator")
    return covered * 100 >= minimum * executable


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cargo", default=os.environ.get("CARGO", "cargo"))
    parser.add_argument("--sqlite-provider", choices=("system", "bundled"), default="system")
    parser.add_argument("--report-dir", type=Path, default=CORE / "target/coverage")
    parser.add_argument("--minimum-line-coverage", type=float, default=92.0)
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args(argv)
    report_dir = args.report_dir.resolve()
    report_dir.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="run-", dir=report_dir))
    report = {"status": "failed", "ui_required": False, "migration_baseline_used": False,
              "platform": {"os": sys.platform, "machine": platform.machine()},
              "sqlite_provider": args.sqlite_provider, "profile": "debug",
              "minimum_line_coverage": args.minimum_line_coverage, "work_dir": str(work),
              "branch_coverage": {"measured": False, "percent": None}, "steps": []}
    env = os.environ.copy()

    def run(name, command, *, output=None):
        result = subprocess.run(command, cwd=CORE, env=env, capture_output=True,
                                text=True, encoding="utf-8", errors="replace", timeout=1800)
        log = work / (name + ".log")
        log.write_text(result.stderr if output else result.stdout + result.stderr)
        if output:
            output.write_text(result.stdout)
        report["steps"].append({"name": name, "command": command, "returncode": result.returncode,
                                "log": str(log), "stdout_file": str(output) if output else None})
        if result.returncode:
            raise RuntimeError(name + " failed: " + (result.stdout + result.stderr)[-3000:])
        return result.stdout.strip()

    try:
        meets_floor(0, 1, args.minimum_line_coverage)
        if sys.platform != "darwin" or platform.machine().lower() not in ("arm64", "aarch64", "x86_64", "amd64"):
            raise ValueError("The reference coverage gate requires native macOS arm64 or x86_64")
        channel = tomllib.loads((CORE / "rust-toolchain.toml").read_text())["toolchain"]["channel"]
        env["RUSTUP_TOOLCHAIN"] = channel
        cargo = shutil.which(args.cargo)
        if not cargo:
            raise ValueError("Cargo executable not found")
        rustup = Path(cargo).parent / "rustup"
        if not rustup.is_file():
            rustup = Path(shutil.which("rustup") or "")
        rustc = run("pinned-rustc", [str(rustup), "which", "--toolchain", channel, "rustc"])
        version = run("rustc-version", [rustc, "-vV"])
        host = re.search(r"^host:\s*(\S+)", version, re.M).group(1)
        sysroot = Path(run("sysroot", [rustc, "--print", "sysroot"]))
        llvm = sysroot / "lib/rustlib" / host / "bin"
        for name in ("llvm-cov", "llvm-profdata"):
            if not (llvm / name).is_file():
                raise ValueError("Missing pinned LLVM tools; prepare with rustup component add llvm-tools-preview --toolchain " + channel)
        report.update(toolchain=channel, target=host, llvm_version=run("llvm-version", [str(llvm / "llvm-cov"), "--version"]))
        report["source_commit"] = run("git-head", ["git", "rev-parse", "HEAD"])
        report["git_status_before"] = run("git-status-before", ["git", "status", "--short", "--branch"])
        run("git-source-diff", ["git", "-C", str(ROOT), "diff", "--no-ext-diff", "HEAD", "--", "Source/Guanyinma"], output=work / "source-diff.patch")
        sources = {p.resolve(): p.read_text() for p in sorted(SOURCE.rglob("*.rs"))}
        report["source_sha256_before"] = {str(p.relative_to(CORE)): digest(p) for p in sources}
        # Validate exclusions before spending time executing the suite.
        for text in sources.values():
            test_only_ranges(text)
        profiles = work / "profiles"
        profiles.mkdir()
        target_base = Path(env.get("CARGO_TARGET_DIR", str(CORE / "target"))).resolve()
        coverage_target = target_base / ("coverage-" + work.name)
        report["target_directory"] = str(coverage_target)
        env.pop("CARGO_ENCODED_RUSTFLAGS", None)
        env.pop("CARGO_BUILD_TARGET", None)
        env.update(CARGO_TARGET_DIR=str(coverage_target), CARGO_INCREMENTAL="0",
                   RUSTFLAGS="-C instrument-coverage -C link-dead-code -C debuginfo=2",
                   LLVM_PROFILE_FILE=str(profiles / "%m-%p.profraw"), CARGO_TERM_COLOR="never")
        report["rustflags"] = env["RUSTFLAGS"]
        if args.sqlite_provider == "system":
            sdk = run("macos-sdk", ["xcrun", "--sdk", "macosx", "--show-sdk-path"])
            env.update(SQLITE3_LIB_DIR=sdk + "/usr/lib", SQLITE3_INCLUDE_DIR=sdk + "/usr/include",
                       SQLITE3_STATIC="0", SQLITE3_NO_PKG_CONFIG="1")
        tests_path = work / "core-tests.json"
        command = [sys.executable, str(CORE / "tools/test-core.py"), "--cargo", cargo,
                   "--profile", "debug", "--target", host, "--sqlite-provider", args.sqlite_provider,
                   "--report", str(tests_path)]
        if args.offline:
            command.append("--offline")
        run("instrumented-tests", command)
        tests = json.loads(tests_path.read_text())
        if tests["status"] != "passed" or not tests["executed"] or not tests["c_abi"]["executed"]:
            raise RuntimeError("Coverage requires passing Rust and real C consumer execution")
        report["tests"] = {"report": str(tests_path), "rust": tests["rust_tests"], "c_abi_checks": tests["c_abi"]["checks"]}
        objects = [Path(item["path"]) for item in tests["test_binaries"]] + [Path(tests["c_abi"]["library"]["path"])]
        raw_profiles = sorted(profiles.glob("*.profraw"))
        if not objects or not all(p.is_file() for p in objects) or not raw_profiles:
            raise RuntimeError("Missing instrumented objects or fresh profiles")
        report["object_sha256"] = {str(p): digest(p) for p in objects}
        report["profile_sha256"] = {str(p): digest(p) for p in raw_profiles}
        merged = work / "merged.profdata"
        run("merge-profiles", [str(llvm / "llvm-profdata"), "merge", "-sparse", *map(str, raw_profiles), "-o", str(merged)])
        raw = work / "raw.lcov"
        run("export-lcov", [str(llvm / "llvm-cov"), "export", str(objects[0]),
                            *[arg for p in objects[1:] for arg in ("-object", str(p))],
                            "-instr-profile=" + str(merged), "-format=lcov", *map(str, sources)], output=raw)
        records, exclusions = production_lines(raw.read_text(), sources)
        files, filtered = [], []
        for path, lines in records.items():
            covered = sum(count > 0 for count in lines.values())
            files.append({"file": str(path.relative_to(CORE)), "covered_lines": covered,
                          "executable_lines": len(lines), "uncovered_lines": sorted(n for n, c in lines.items() if c == 0),
                          "line_coverage_percent": round(covered * 100 / len(lines), 2) if lines else None,
                          "excluded_test_ranges": exclusions[path]})
            if lines:
                filtered += ["TN:Guanyinma production source", "SF:" + str(path),
                             *[f"DA:{n},{c}" for n, c in sorted(lines.items())],
                             f"LF:{len(lines)}", f"LH:{covered}", "end_of_record"]
        (report_dir / "production-only.lcov").write_text("\n".join(filtered) + "\n")
        covered = sum(row["covered_lines"] for row in files)
        executable = sum(row["executable_lines"] for row in files)
        passed = meets_floor(covered, executable, args.minimum_line_coverage)
        report.update(status="passed" if passed else "below_floor", files=files,
                      line_coverage={"covered": covered, "executable": executable,
                                     "uncovered": executable - covered, "percent": round(covered * 100 / executable, 2)},
                      profile_count=len(raw_profiles), object_count=len(objects),
                      scope="Compiled production src/*.rs executable lines; inline test-only items and dependencies excluded")
        report["source_sha256_after"] = {str(p.relative_to(CORE)): digest(p) for p in sources}
        if report["source_sha256_before"] != report["source_sha256_after"]:
            raise RuntimeError("Source changed during coverage execution")
        report["git_status_after"] = run("git-status-after", ["git", "status", "--short", "--branch"])
    except (OSError, ValueError, KeyError, AttributeError, RuntimeError, subprocess.SubprocessError) as error:
        report.update(status="failed", error=str(error))
    (report_dir / "coverage-summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print("Guanyinma coverage:", report["status"], report.get("line_coverage", {}))
    print("Report:", report_dir / "coverage-summary.json")
    if report.get("error"):
        print(report["error"], file=sys.stderr)
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
