#!/bin/bash
# Explicit host-link preparation for ordinary Swift package tests, without UI.
set -euo pipefail
core_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
repository="$(cd "$core_dir/../.." && pwd -P)"
package_dir="${KEYKEY_SWIFT_PACKAGE_PATH:-$repository/Source/Loaders/iOS-Keyboard/KeyKeyEngine}"
host_output="${KEYKEY_GUANYINMA_HOST_BUILD_DIR:-$repository/Installer/local-builds/guanyinma-ios-swift-host}"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
PLATFORM_NAME=macosx ARCHS="$(uname -m)" GUANYINMA_OUTPUT_DIR="$host_output" \
    bash "$core_dir/tools/build-ios-core.sh"
host_output="$(cd "$host_output" && pwd -P)"
exec swift test --package-path "$package_dir" -Xlinker "-L$host_output" "$@"
