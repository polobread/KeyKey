#!/usr/bin/env python3
"""Require actual, non-skipped JNI smoke execution in Gradle JUnit XML output."""
import argparse
from pathlib import Path
import xml.etree.ElementTree as ET

CLASSES = ("GuanyinmaNativeTest", "GuanyinmaIntegrationTest", "GuanyinmaUserDataTest")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results", type=Path)
    args = parser.parse_args()
    suites = {}
    for path in args.results.glob("TEST-*.xml"):
        root = ET.parse(path).getroot()
        for suite in ([root] if root.tag == "testsuite" else root.findall("testsuite")):
            suites[suite.get("name", "").rsplit(".", 1)[-1]] = suite
    total = 0
    for name in CLASSES:
        suite = suites.get(name)
        if suite is None:
            raise RuntimeError("Missing JNI smoke result: " + name)
        tests = int(suite.get("tests", "0"))
        failed = sum(int(suite.get(key, "0")) for key in ("failures", "errors", "skipped"))
        if tests <= 0 or failed:
            raise RuntimeError(f"JNI smoke {name} must execute tests with zero failures/errors/skips")
        total += tests
    print(f"True host JNI smoke: {total} tests executed, 0 skipped across {len(CLASSES)} classes.")


if __name__ == "__main__":
    main()
