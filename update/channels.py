# Copyright (c) 2026 Chui Ping Cheng. MIT License.
"""Strict release/channel mapping shared by packaging and updater tooling."""
import re

VERSION = r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"


def parse_version(version):
    match = re.fullmatch(rf"({VERSION})(?:-beta([1-9]\d*))?", version)
    if not match:
        raise ValueError("version must be x.y.z or x.y.z-betaN (N >= 1)")
    base, beta = match.groups()
    return base, "beta" if beta else "stable", beta


def release_version(tag, product_version):
    base, channel, _ = parse_version(product_version)
    if channel != "stable":
        raise ValueError("product version must be x.y.z")
    if not tag:
        return base
    if not tag.startswith("v") or parse_version(tag[1:])[0] != base:
        raise ValueError(f"Release tag must be v{base} or v{base}-betaN, received {tag!r}")
    return tag[1:]


def native_version(version):
    base, _, beta = parse_version(version)
    # Sparkle/WinSparkle compare the same machine version; stable follows bN.
    return f"{base}b{beta}" if beta else base
