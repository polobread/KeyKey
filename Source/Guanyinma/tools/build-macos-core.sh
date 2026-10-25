#!/bin/bash
# Build the optional Rust backend for the native macOS target. No database cooking.
set -euo pipefail

case "${KEYKEY_ENABLE_GUANYINMA:-0}" in
    0) exit 0 ;;
    1) ;;
    *) echo "error: KEYKEY_ENABLE_GUANYINMA must be 0 or 1" >&2; exit 1 ;;
esac

core_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
: "${DERIVED_FILE_DIR:?Build through Xcode or provide DERIVED_FILE_DIR}"
: "${ARCHS:?Build through Xcode or provide ARCHS}"
output_dir="$DERIVED_FILE_DIR/Guanyinma"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd -P)"

if [[ -n "${CARGO:-}" ]]; then
    cargo_bin="$CARGO"
elif command -v cargo >/dev/null 2>&1; then
    cargo_bin="$(command -v cargo)"
elif [[ -n "${CARGO_HOME:-}" && -x "$CARGO_HOME/bin/cargo" ]]; then
    cargo_bin="$CARGO_HOME/bin/cargo"
else
    echo "error: Guanyinma requires the pinned Rust toolchain; set CARGO or add cargo to PATH" >&2
    exit 1
fi
if ! cargo_bin="$(command -v "$cargo_bin")"; then
    echo "error: CARGO must name an executable cargo command" >&2
    exit 1
fi
# Resolve a caller-provided relative executable before changing into the crate.
if [[ "$cargo_bin" == */* ]]; then
    cargo_bin="$(cd "$(dirname "$cargo_bin")" && pwd -P)/$(basename "$cargo_bin")"
fi

# Use the same SDK SQLite provider as the existing Objective-C++ core. Do not
# resolve Homebrew's pkg-config SQLite or enable the bundled-sqlite feature.
if [[ -n "${SDKROOT:-}" && -d "$SDKROOT" ]]; then
    sdk_path="$SDKROOT"
else
    sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
fi
export SQLITE3_LIB_DIR="$sdk_path/usr/lib"
export SQLITE3_INCLUDE_DIR="$sdk_path/usr/include"
export SQLITE3_STATIC=0
export SQLITE3_NO_PKG_CONFIG=1

cargo_args=(build --lib --release --locked --no-default-features --target-dir "$output_dir/target")
case "${KEYKEY_GUANYINMA_OFFLINE:-0}" in
    0) ;;
    1) cargo_args+=(--offline) ;;
    *) echo "error: KEYKEY_GUANYINMA_OFFLINE must be 0 or 1" >&2; exit 1 ;;
esac

archives=()
# Cargo runs from the crate so rustup honors its committed rust-toolchain.toml.
cd "$core_dir"
for architecture in $ARCHS; do
    case "$architecture" in
        arm64) rust_target=aarch64-apple-darwin ;;
        x86_64) rust_target=x86_64-apple-darwin ;;
        *) echo "error: unsupported Guanyinma macOS architecture: $architecture" >&2; exit 1 ;;
    esac
    "$cargo_bin" "${cargo_args[@]}" --target "$rust_target"
    archives+=("$output_dir/target/$rust_target/release/libguanyinma.a")
done

# A stable output path lets Xcode track the archive before its link phase.
# Publish a complete archive atomically, and keep its timestamp when unchanged.
# Unique staging files also keep concurrent invocations from sharing a temp file.
staged_archive="$(mktemp "$output_dir/libguanyinma.a.XXXXXX")"
trap 'rm -f "$staged_archive"' EXIT
if [[ ${#archives[@]} -eq 1 ]]; then
    cp "${archives[0]}" "$staged_archive"
else
    xcrun lipo -create "${archives[@]}" -output "$staged_archive"
fi
if ! cmp -s "$staged_archive" "$output_dir/libguanyinma.a"; then
    mv -f "$staged_archive" "$output_dir/libguanyinma.a"
fi
