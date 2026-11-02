#!/usr/bin/env python3
"""Keep the additive six-platform workflow small; execute the shared core entry.

The Android action runs one script in one Actions step, so configure SDK values
in-process rather than relying on GITHUB_ENV becoming visible mid-step.
"""
import argparse
from pathlib import Path
import subprocess
import sys

import configure


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("linux", "macos", "windows", "freebsd", "ios", "android"))
    parser.add_argument("--sqlite-provider", choices=("system", "bundled"))
    parser.add_argument("--ndk")
    parser.add_argument("--api", default="26")
    parser.add_argument("--serial", default="emulator-5554")
    parser.add_argument("--remote-root")
    parser.add_argument("--checks-only", action="store_true")
    args = parser.parse_args()
    if args.checks_only:
        for command in (
            [sys.executable, "-m", "unittest", "discover", "-s", str(Path(__file__).parent), "-p", "test_*.py", "-v"],
            ["cargo", "fmt", "--manifest-path", str(configure.CORE / "Cargo.toml"), "--check"],
            ["cargo", "clippy", "--manifest-path", str(configure.CORE / "Cargo.toml"), "--locked", "--all-targets", "--", "-D", "warnings"],
        ):
            subprocess.run(command, check=True)
        return 0
    if not args.platform or not args.sqlite_provider:
        parser.error("--platform and --sqlite-provider are required for target execution")
    report = configure.ROOT / "artifacts/guanyinma-core" / args.platform / "report.json"
    if args.platform == "ios":
        args.metadata = report.with_name("simulator.json")
        configure.configure_ios(args)
    elif args.platform == "android":
        if not args.ndk or not args.remote_root:
            parser.error("Android execution requires --ndk and --remote-root")
        configure.configure_android(args)
    else:
        configure.native(args)
    values = configure.OUTPUT_VALUES
    command = [sys.executable, str(configure.CORE / "tools/test-core.py"), "--release",
               "--sqlite-provider", args.sqlite_provider, "--cc-json", values["cc_json"], "--report", str(report)]
    if "target" in values:
        command += ["--target", values["target"], "--runner-json", values["runner_json"]]
    return subprocess.run(command).returncode


if __name__ == "__main__":
    raise SystemExit(main())
