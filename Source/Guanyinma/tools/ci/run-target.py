#!/usr/bin/env python3
"""Cargo/C-consumer execution transport for headless CI targets.

This runs an already compiled target executable. It neither builds a frontend nor
opens a simulator UI. A transport success never replaces the test's exit status.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import uuid


class TransportError(RuntimeError):
    pass


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def command(argv, *, env=None, check=True, timeout=300):
    result = subprocess.run(argv, env=env, capture_output=True, timeout=timeout)
    if check and result.returncode:
        raise TransportError(f"{shlex.join(argv)} failed ({result.returncode}): "
                             + result.stderr.decode("utf-8", errors="replace"))
    return result


def forward(result):
    sys.stdout.buffer.write(result.stdout)
    sys.stdout.buffer.flush()
    sys.stderr.buffer.write(result.stderr)
    sys.stderr.buffer.flush()


def model_path():
    value = os.environ.get("GUANYINMA_TEST_MODEL_PATH")
    if not value:
        raise TransportError("GUANYINMA_TEST_MODEL_PATH must name the staged test model")
    path = Path(value).resolve(strict=True)
    if not path.is_file():
        raise TransportError("test model must be a regular file")
    return path


def remote_root(value):
    if not re.fullmatch(r"/data/local/tmp/guanyinma-core-[A-Za-z0-9_-]+", value):
        raise TransportError("remote root must be a unique /data/local/tmp/guanyinma-core-NAME")
    return value


def run_android(args, report):
    prefix = [args.adb, "-s", args.serial]
    remote = remote_root(args.remote_root)
    model = model_path()
    before = digest(model)
    executable = args.executable.resolve(strict=True)
    if not executable.is_file():
        raise TransportError("target executable must be a regular file")
    binary_name = re.sub(r"[^A-Za-z0-9_.-]", "_", executable.name) + "-" + digest(executable)[:12]
    binary = remote + "/bin/" + binary_name
    remote_model = remote + "/model/KeyKey.db"
    libraries = remote + "/lib"
    user_root = remote + "/user/" + uuid.uuid4().hex

    def shell(argv, *, check=True):
        return command(prefix + ["shell", " ".join(shlex.quote(str(part)) for part in argv)],
                       check=check, timeout=args.timeout)

    shell(["mkdir", "-p", remote + "/bin", remote + "/model", libraries, remote + "/tmp", user_root])
    command(prefix + ["push", str(executable), binary], timeout=args.timeout)
    shell(["chmod", "755", binary])
    existing = shell(["toybox", "sha256sum", remote_model], check=False)
    existing_hash = existing.stdout.decode().split() if existing.returncode == 0 else []
    if not existing_hash or existing_hash[0] != before:
        command(prefix + ["push", str(model), remote_model], timeout=args.timeout)
    shell(["chmod", "444", remote_model])
    initial = shell(["toybox", "sha256sum", remote_model]).stdout.decode().split()[0]
    if initial != before:
        raise TransportError("Android model copy hash differs before execution")
    library_dir = os.environ.get("GUANYINMA_TEST_NATIVE_LIBRARY_DIR")
    staged_libraries = []
    if library_dir:
        for path in sorted(Path(library_dir).glob("*.so*")):
            if path.is_file():
                command(prefix + ["push", str(path), libraries + "/" + path.name], timeout=args.timeout)
                staged_libraries.append(path.name)
    mapping = {str(model): remote_model, os.environ["GUANYINMA_TEST_MODEL_PATH"]: remote_model}
    host_user = os.environ.get("GUANYINMA_TEST_USER_DATABASE_PATH")
    remote_user = None
    if host_user:
        user_path = Path(host_user).absolute()
        remote_user = user_root + "/" + user_path.name
        mapping[host_user] = remote_user
        mapping[str(user_path)] = remote_user
        for suffix in ("", "-wal", "-shm"):
            path = Path(str(user_path) + suffix)
            if path.is_file():
                command(prefix + ["push", str(path), remote_user + suffix], timeout=args.timeout)
    argv = [mapping.get(value, value) for value in args.arguments]
    environment = ["GUANYINMA_TEST_MODEL_PATH=" + remote_model,
                   "GUANYINMA_TEST_NATIVE_LIBRARY_DIR=" + libraries,
                   "LD_LIBRARY_PATH=" + libraries, "TMPDIR=" + remote + "/tmp"]
    if remote_user:
        environment.append("GUANYINMA_TEST_USER_DATABASE_PATH=" + remote_user)
    report.update(device=args.serial, executable=str(executable), remote_executable=binary,
                  model_host_path=str(model), model_remote_path=remote_model, model_sha256_before=initial,
                  staged_libraries=staged_libraries, remote_arguments=argv)
    report["executed"] = True
    result = shell(["env", *environment, binary, *argv], check=False)
    forward(result)
    report["test_returncode"] = result.returncode
    after = shell(["toybox", "sha256sum", remote_model]).stdout.decode().split()[0]
    report["model_sha256_after"] = after
    if digest(model) != before or after != before:
        raise TransportError("test model changed during Android execution")
    if remote_user:
        pulled = []
        for suffix in ("", "-wal", "-shm"):
            remote_path = remote_user + suffix
            if shell(["test", "-f", remote_path], check=False).returncode == 0:
                destination = Path(host_user + suffix)
                destination.parent.mkdir(parents=True, exist_ok=True)
                command(prefix + ["pull", remote_path, str(destination)], timeout=args.timeout)
                pulled.append({"remote_path": remote_path, "host_path": str(destination),
                               "size": destination.stat().st_size, "sha256": digest(destination)})
        report["pulled_user_database_files"] = pulled
        if result.returncode == 0 and not any(row["remote_path"] == remote_user for row in pulled):
            raise TransportError("successful C consumer did not produce its requested Unicode user database")
    return result.returncode


def run_ios(args, report):
    executable = args.executable.resolve(strict=True)
    model = model_path()
    before = digest(model)
    environment = os.environ.copy()
    with tempfile.TemporaryDirectory(prefix="guanyinma-ios-core-") as scratch:
        environment["SIMCTL_CHILD_GUANYINMA_TEST_MODEL_PATH"] = str(model)
        environment["SIMCTL_CHILD_TMPDIR"] = scratch
        library_dir = os.environ.get("GUANYINMA_TEST_NATIVE_LIBRARY_DIR")
        if library_dir:
            for path in sorted(Path(library_dir).glob("*.dylib")):
                if path.is_file():
                    command(["codesign", "--force", "--sign", "-", str(path)])
            environment["SIMCTL_CHILD_DYLD_LIBRARY_PATH"] = library_dir
            environment["SIMCTL_CHILD_GUANYINMA_TEST_NATIVE_LIBRARY_DIR"] = library_dir
        user_path = os.environ.get("GUANYINMA_TEST_USER_DATABASE_PATH")
        if user_path:
            environment["SIMCTL_CHILD_GUANYINMA_TEST_USER_DATABASE_PATH"] = user_path
        command(["codesign", "--force", "--sign", "-", str(executable)])
        argv = ["xcrun", "simctl", "spawn", args.device, str(executable), *args.arguments]
        report.update(device=args.device, command=argv, executable=str(executable),
                      model_host_path=str(model), model_sha256_before=before, executed=True)
        result = command(argv, env=environment, check=False, timeout=args.timeout)
        forward(result)
        report["test_returncode"] = result.returncode
        report["model_sha256_after"] = digest(model)
        if report["model_sha256_after"] != before:
            raise TransportError("test model changed during iOS simulator execution")
        return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="platform", required=True)
    android = sub.add_parser("android")
    android.add_argument("--adb", default="adb")
    android.add_argument("--serial", required=True)
    android.add_argument("--remote-root", required=True)
    ios = sub.add_parser("ios")
    ios.add_argument("--device", required=True)
    for target in (android, ios):
        target.add_argument("--timeout", type=int, default=300)
        target.add_argument("executable", type=Path)
        target.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    report = dict(schema_version=1, kind="guanyinma_target_execution", platform=args.platform,
                  started_at=datetime.now(timezone.utc).isoformat(), executed=False, status="failed")
    code = 1
    try:
        code = run_android(args, report) if args.platform == "android" else run_ios(args, report)
        report["status"] = "passed" if code == 0 else "failed"
    except (OSError, subprocess.SubprocessError, TransportError) as error:
        report["error"] = str(error)
        print("Guanyinma target execution failed: " + str(error), file=sys.stderr)
    finally:
        folder = os.environ.get("GUANYINMA_TEST_RUNNER_REPORT_DIR")
        if folder:
            path = Path(folder)
            path.mkdir(parents=True, exist_ok=True)
            (path / (args.platform + "-" + args.executable.name + "-" + uuid.uuid4().hex + ".json")).write_text(
                json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
