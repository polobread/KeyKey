#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_build="$(mktemp -d)"
trap 'rm -rf "$task_build"' EXIT
sdk="$task_root/update/.cache/macos-2.10.0"
if [[ ! -d "$sdk/Sparkle.framework" ]]; then
    echo 'Prepare the pinned SDK first: python3 update/prepare.py fetch macos' >&2
    exit 1
fi
xcrun clang -fblocks -fno-objc-arc -mmacosx-version-min=15.0 \
    -F "$sdk" -framework Cocoa \
    "$task_root/Source/Loaders/OSX-IMK/KeyKeyMacUpdater.m" \
    "$task_root/Source/Loaders/OSX-IMK/Tests/MacUpdaterTests.m" \
    -o "$task_build/mac-updater-tests"
KEYKEY_TEST_SPARKLE_FRAMEWORK="$sdk/Sparkle.framework" "$task_build/mac-updater-tests"
xcrun clang -fno-objc-arc -mmacosx-version-min=15.0 -framework Cocoa \
    '-DOPENVANILLA_DO_CONNECTION_NAME=@"io.github.polobread.KeyKeyUpdaterIsolatedTest"' \
    -I "$task_root/Source/Loaders/OSX-IMK" -I "$task_root/Source/Frameworks/LFExtensions" \
    "$task_root/Source/PreferenceApplications/OSX/TakaoUpdate.m" \
    "$task_root/Source/Loaders/OSX-IMK/Tests/MacUpdatePreferencesTests.m" \
    -o "$task_build/mac-update-preferences-tests"
"$task_build/mac-update-preferences-tests"
