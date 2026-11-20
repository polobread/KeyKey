#!/usr/bin/env python3
"""Exercise the actual bound candidate-click methods without IMK, windows or global keys."""
from pathlib import Path
import argparse
import hashlib
import subprocess
import tempfile

LOADER = Path(__file__).resolve().parents[1]

def method(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    level, end = 1, opening + 1
    while level:
        level += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]

def objc_class(source, name):
    first = source.index("@interface " + name)
    implementation = source.index("@implementation " + name, first)
    return source[first:source.index("@end", implementation) + len("@end")]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", type=Path, help="Retain generated source and source hashes")
    args = parser.parse_args()
    controller = (LOADER / "OpenVanillaController.mm").read_text()
    signatures = ["+ (void)setActiveContext:", "+ (id)candidateSelectionTargetForPanel:",
        "+ (void)invalidateCandidateSelectionTarget:", "+ (BOOL)candidateSelectionTargetIsCurrent:",
        "+ (BOOL)selectCandidateAtIndex:"]
    actual = "\n".join(method(controller, signature) for signature in signatures)
    sources = {"OpenVanillaController.mm": controller}
    inserts = {"// ACTUAL_TARGET_CLASS": objc_class(controller, "OVCCandidateSelectionTarget"),
        "// ACTUAL_CONTROLLER_METHODS": actual}
    for orientation in ("Vertical", "Horizontal"):
        name = "CV" + orientation + "CandidateController.mm"
        source = (LOADER / name).read_text()
        sources[name] = source
        methods = "\n".join(method(source, signature) for signature in
            ("- (void)hide", "- (IBAction)sendKey:", "- (IBAction)gotoNextPage:", "- (IBAction)gotoPreviousPage:"))
        display = method(source, "- (void)updateDisplay:")
        assert "invalidateCandidateSelectionTarget:_selectionTarget" in display
        assert "candidateSelectionTargetForPanel:panel" in display
        inserts["// ACTUAL_" + orientation.upper() + "_METHODS"] = methods
        actual += "\n" + methods
    # Candidate mouse actions must never pass through the real hardware-event
    # handler, manufacture NSEvents, or schedule the legacy global key sender.
    for forbidden in ("CGEventPost", "CVSendKey", "NSEvent", "handleEvent:", "afterDelay:", "_handledKeyCodes"):
        assert forbidden not in actual, "Candidate dispatch must not use " + forbidden
    assert "setActiveContext:nil sender:nil" in method(controller, "- (void)deactivateServer:")
    fixture = (LOADER / "Tests/MacCandidateSelectionTests.mm").read_text()
    for marker, value in inserts.items():
        assert fixture.count(marker) == 1, marker
        fixture = fixture.replace(marker, value)
    with tempfile.TemporaryDirectory(prefix="keykey-candidate-selection-tests-") as scratch:
        tmp = Path(scratch)
        for name in ("OpenVanilla", "PlainVanilla"):
            framework = tmp / (name + ".framework")
            framework.mkdir()
            (framework / "Headers").symlink_to(LOADER.parents[1] / "Frameworks" / name / "Headers", target_is_directory=True)
        generated = tmp / "candidate-selection.mm"
        generated.write_text(fixture)
        if args.artifacts:
            import json
            args.artifacts.mkdir(parents=True, exist_ok=True)
            (args.artifacts / generated.name).write_text(fixture)
            (args.artifacts / "source-hashes.json").write_text(json.dumps({name: hashlib.sha256(value.encode()).hexdigest()
                for name, value in sources.items()}, indent=2) + "\n")
        binary = tmp / "candidate-selection"
        subprocess.run(["xcrun", "clang++", "-std=c++17", "-fno-objc-arc", "-Wno-deprecated-declarations",
            "-Wno-parentheses", "-Wno-dangling-else", "-F", str(tmp), "-I", str(LOADER),
            "-I", str(LOADER.parents[1] / "Frameworks/PlainVanilla/Headers"),
            "-I", str(LOADER.parents[1] / "Frameworks/CareService/Headers"),
            "-framework", "Cocoa", str(generated), "-o", str(binary)], check=True, timeout=90)
        subprocess.run([str(binary)], check=True, timeout=30)

if __name__ == "__main__":
    main()
