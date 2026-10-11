#!/usr/bin/env python3
"""Re-sign nested Mach-O code and bundles inside-out (including Sparkle XPC)."""
import argparse
from pathlib import Path
import subprocess


def sign(app, identity):
    magic = {b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf",
             b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
             b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}
    targets = []
    for path in app.rglob("*"):
        if path.is_symlink():
            continue
        if path.is_dir() and path.suffix in (".app", ".framework", ".xpc", ".bundle"):
            targets.append(path)
        elif path.is_file():
            with path.open("rb") as stream:
                if stream.read(4) in magic:
                    targets.append(path)
    targets.append(app)
    for path in sorted(targets, key=lambda p: len(p.parts), reverse=True):
        command = ["codesign", "--force", "--preserve-metadata=entitlements", "--sign", identity]
        if identity != "-":
            command += ["--options", "runtime", "--timestamp"]
        subprocess.run([*command, str(path)], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("identity")
    args = parser.parse_args()
    sign(args.app, args.identity)
