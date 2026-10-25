#!/usr/bin/env python3
"""Test actual loader backend-token checks without IMK, SQLite, or user profiles."""
from pathlib import Path
import subprocess
import tempfile

LOADER = Path(__file__).resolve().parents[1]
source = (LOADER / "OpenVanillaLoader.mm").read_text()


def method(signature):
    start = source.index(signature)
    opening = source.index("{", start)
    end, depth = opening + 1, 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


methods = "\n".join(method(signature) for signature in [
    "- (NSString *)userPhraseDBBackendIdentifier",
    "- (BOOL)applyUserPhraseEdit:",
])
fixture = (LOADER / "Tests/GuanyinmaMacAdministrationTests.m").read_text()
with tempfile.TemporaryDirectory(prefix="keykey-core-administration-") as scratch:
    tmp = Path(scratch)
    test = tmp / "administration.m"
    test.write_text(fixture.replace("// ACTUAL_LOADER_METHODS", methods))
    executable = tmp / "administration"
    subprocess.run(["xcrun", "clang", "-fno-objc-arc", "-fblocks",
                    "-DKEYKEY_ENABLE_GUANYINMA=1", "-framework", "Foundation",
                    str(test), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
