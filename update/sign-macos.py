#!/usr/bin/env python3
"""Re-sign nested code, preserving runtime entitlements but never debug access."""
import argparse
from pathlib import Path
import plistlib
import subprocess
import tempfile
from xml.parsers.expat import ExpatError


DEBUG_ENTITLEMENT = "com.apple.security.get-task-allow"


def signing_targets(app):
    if not app.is_dir() or app.is_symlink():
        raise ValueError(f"Expected an app directory: {app}")
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
    return sorted(targets, key=lambda p: (-len(p.parts), str(p)))


def architectures(path):
    # Bundles are signed after their executable, whose slices have already been
    # checked. Inspect every slice of files, not just the runner's native arch.
    if path.is_dir():
        return [None]
    result = subprocess.run(["lipo", "-archs", str(path)], check=True, capture_output=True)
    names = result.stdout.decode().split()
    if not names:
        raise ValueError(f"No Mach-O architectures: {path}")
    return names


def read_entitlements(path, architecture=None, allow_unsigned=False):
    command = ["codesign", "--display", "--entitlements", "-", "--xml"]
    if architecture:
        command += ["--architecture", architecture]
    result = subprocess.run([*command, str(path)], capture_output=True)
    if result.returncode:
        if allow_unsigned and b"code object is not signed at all" in result.stderr:
            return {}
        raise ValueError(f"Cannot read entitlements: {path} ({architecture or 'bundle'})")
    if not result.stdout.strip():
        return {}
    try:
        entitlements = plistlib.loads(result.stdout)
    except (ValueError, plistlib.InvalidFileException, ExpatError) as error:
        raise ValueError(f"Invalid entitlement plist: {path}") from error
    if not isinstance(entitlements, dict):
        raise ValueError(f"Entitlements are not a dictionary: {path}")
    return entitlements


def distribution_entitlements(path):
    sanitized = []
    for architecture in architectures(path):
        entitlements = read_entitlements(path, architecture, allow_unsigned=True)
        entitlements.pop(DEBUG_ENTITLEMENT, None)
        sanitized.append(entitlements)
    if any(value != sanitized[0] for value in sanitized[1:]):
        # codesign applies one plist to all slices. Never silently discard
        # architecture-specific sandbox/XPC permissions by copying just one.
        raise ValueError(f"Different runtime entitlements across architectures: {path}")
    return sanitized[0]


def verify(app):
    subprocess.run(["codesign", "--verify", "--deep", "--strict",
                    "--all-architectures", str(app)], check=True)
    for path in signing_targets(app):
        for architecture in architectures(path):
            if DEBUG_ENTITLEMENT in read_entitlements(path, architecture):
                raise ValueError(f"Distribution contains {DEBUG_ENTITLEMENT}: {path} ({architecture})")


def sign(app, identity):
    with tempfile.TemporaryDirectory(prefix="keykey-sign-entitlements-") as scratch:
        entitlement_file = Path(scratch) / "entitlements.plist"
        for path in signing_targets(app):
            expected = distribution_entitlements(path)
            entitlement_file.write_bytes(plistlib.dumps(expected))
            # An explicit (possibly empty) plist replaces inherited debug
            # access without dropping Sparkle's sandbox/XPC permissions.
            command = ["codesign", "--force", "--entitlements", str(entitlement_file), "--sign", identity]
            if identity != "-":
                command += ["--options", "runtime", "--timestamp"]
            if expected:
                # macOS 15 otherwise omits entitlements from dylib signatures.
                command += ["--force-library-entitlements"]
            subprocess.run([*command, str(path)], check=True)
            for architecture in architectures(path):
                if read_entitlements(path, architecture) != expected:
                    raise ValueError(f"Entitlements changed during signing: {path} ({architecture})")
    verify(app)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("identity", nargs="?")
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    if args.verify_only:
        verify(args.app)
    elif args.identity:
        sign(args.app, args.identity)
    else:
        parser.error("identity is required unless --verify-only is used")
