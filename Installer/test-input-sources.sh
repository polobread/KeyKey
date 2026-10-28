#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_build="$(mktemp -d)"
trap 'rm -rf "$task_build"' EXIT

xcrun clang -fno-objc-arc -mmacosx-version-min=15.0 -arch arm64 -Wall -Wextra \
    -framework Cocoa -framework Carbon "$task_root/Installer/InputSourceTool.m" \
    -o "$task_build/KeyKeyInputSourceTool"
# Rejects arguments before reaching any TIS mutation.
set +e
"$task_build/KeyKeyInputSourceTool" --invalid
status=$?
set -e
[[ "$status" == 64 ]]

xcrun clang -fno-objc-arc -mmacosx-version-min=15.0 -arch arm64 -framework Cocoa -framework Carbon \
    "$task_root/Installer/Tests/InputSourceToolTests.m" -o "$task_build/input-source-tests"
"$task_build/input-source-tests"

xcrun clang -fno-objc-arc -mmacosx-version-min=15.0 -arch arm64 -Wall -Wextra -framework Cocoa -framework Carbon \
    "$task_root/Installer/Tests/SystemInputSourceTests.m" -o "$task_build/system-input-source-tests"
"$task_build/system-input-source-tests"

xcrun clang -fno-objc-arc -mmacosx-version-min=15.0 -arch arm64 -Wall -Wextra -framework Cocoa -framework Carbon \
    "$task_root/Installer/Tests/ProcessExitTests.m" -o "$task_build/process-exit-tests"
"$task_build/process-exit-tests"

xcrun clang -fno-objc-arc -mmacosx-version-min=15.0 -arch arm64 -Wall -Wextra -framework Cocoa -framework Carbon \
    "$task_root/Installer/Tests/DatabaseIdentityTests.m" -o "$task_build/database-identity-tests"
"$task_build/database-identity-tests"

xcrun clang -fno-objc-arc -mmacosx-version-min=15.0 -arch arm64 -framework Cocoa -framework Carbon \
    -DTISCreateInputSourceList=KKTestCreateInputSourceList \
    -DTISGetInputSourceProperty=KKTestGetInputSourceProperty \
    "$task_root/Source/Loaders/OSX-IMK/CVKeyboardHelper.m" \
    "$task_root/Source/Loaders/OSX-IMK/Tests/KeyboardHelperTests.m" \
    -o "$task_build/keyboard-helper-tests"
"$task_build/keyboard-helper-tests"
xcrun clang -fno-objc-arc -mmacosx-version-min=15.0 -arch arm64 -Wall -Wextra \
    -framework Foundation -framework JavaScriptCore \
    "$task_root/Installer/Tests/DistributionTests.m" -o "$task_build/distribution-tests"
"$task_build/distribution-tests" "$task_root/Installer"
python3 "$task_root/Installer/Tests/test_postinstall.py"
