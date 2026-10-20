#!/usr/bin/env python3
"""Test the real IMK input-mode handlers in isolation; never connect to installed IMK."""
from pathlib import Path
import subprocess
import tempfile

loader = Path(__file__).resolve().parents[1]
source = (loader / "OpenVanillaController.mm").read_text()

def method(signature):
    start = source.index(signature)
    opening = source.index("{", start)
    level = 1
    end = opening + 1
    while level:
        if source[end] == "{":
            level += 1
        elif source[end] == "}":
            level -= 1
        end += 1
    return source[start:end]

methods = "\n".join(method(signature) for signature in [
    "- (BOOL)_finishCompositionForModeSwitch:",
    "- (BOOL)_setEnglishMode:", "- (void)_handleShiftTap:",
    "- (void)switchInputMethodAction:", "- (void)englishInputModeAction:"])
assert "[self _handleShiftTap:event client:sender];" in method("- (BOOL)handleEvent:")
assert "_shiftTap.reset();" in method("- (void)activateServer:")
assert "_shiftTap.reset();" in method("- (void)deactivateServer:")
assert "_shiftTapEnabled = NO;" in method("- (void)deactivateServer:")
assert "if (_modeSwitchInProgress)" in method("- (void)commitComposition:")
handling = method("- (BOOL)handleEvent:")
assert handling.index("if (OVCInputMode.english)") < handling.index("_context->handleKeyEvent(&key)")
assert "NSFlagsChangedMask" in method("- (NSUInteger)recognizedEvents:")
assert "KeyKeyIMKShiftProbeEnabled" not in source
fixture = (loader / "Tests/MacInputModeTests.mm").read_text().replace("// ACTUAL_METHODS", methods)
with tempfile.TemporaryDirectory(prefix="keykey-imk-mode-tests-") as scratch:
    tmp = Path(scratch)
    framework = tmp / "OpenVanilla.framework"
    framework.mkdir()
    (framework / "Headers").symlink_to(loader.parents[1] / "Frameworks/OpenVanilla/Headers", target_is_directory=True)
    common = ["xcrun", "clang++", "-std=c++17", "-I", str(loader)]
    subprocess.run([*common, str(loader / "Tests/IMKShiftTapTests.cpp"), "-o", str(tmp / "state")], check=True)
    subprocess.run([str(tmp / "state")], check=True)
    (tmp / "mode.mm").write_text(fixture)
    subprocess.run([*common, "-fobjc-arc", "-Wno-deprecated-declarations", "-Wno-parentheses", "-Wno-dangling-else",
                    "-F", str(tmp), "-I", str(loader.parents[1] / "Frameworks/PlainVanilla/Headers"),
                    "-framework", "Cocoa", str(tmp / "mode.mm"), "-o", str(tmp / "mode")], check=True)
    subprocess.run([str(tmp / "mode")], check=True)
