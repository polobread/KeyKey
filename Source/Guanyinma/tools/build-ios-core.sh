#!/bin/bash
# Build shared Rust ABI archives for iOS or a macOS Swift-package test host.
# No frontend, simulator boot, model cooking or test execution occurs here.
set -euo pipefail

core_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
platform="${GUANYINMA_APPLE_PLATFORM:-${PLATFORM_NAME:-}}"
case "$platform" in
    iphoneos|iphonesimulator|macosx) ;;
    *) echo "error: set PLATFORM_NAME to iphoneos/iphonesimulator (macosx for host tests)" >&2; exit 1 ;;
esac
: "${ARCHS:?Set ARCHS to the requested Apple architectures}"
if [[ -n "${GUANYINMA_OUTPUT_DIR:-}" ]]; then
    output_dir="$GUANYINMA_OUTPUT_DIR"
else
    : "${BUILT_PRODUCTS_DIR:?Build through Xcode or provide GUANYINMA_OUTPUT_DIR}"
    output_dir="$BUILT_PRODUCTS_DIR/Guanyinma/$platform"
fi
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd -P)"

if [[ -n "${CARGO:-}" ]]; then
    cargo_bin="$CARGO"
elif command -v cargo >/dev/null 2>&1; then
    cargo_bin="$(command -v cargo)"
elif [[ -n "${CARGO_HOME:-}" && -x "$CARGO_HOME/bin/cargo" ]]; then
    cargo_bin="$CARGO_HOME/bin/cargo"
elif [[ -x "$HOME/.cargo/bin/cargo" ]]; then
    cargo_bin="$HOME/.cargo/bin/cargo"
else
    echo "error: install the Rust toolchain pinned in Source/Guanyinma/rust-toolchain.toml" >&2
    exit 1
fi
if ! cargo_bin="$(command -v "$cargo_bin")"; then
    echo "error: CARGO must name an executable cargo command" >&2; exit 1
fi
if [[ "$cargo_bin" == */* ]]; then
    cargo_bin="$(cd "$(dirname "$cargo_bin")" && pwd -P)/$(basename "$cargo_bin")"
fi
pinned_toolchain="$(sed -nE 's/^[[:space:]]*channel[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$core_dir/rust-toolchain.toml")"
if [[ -z "$pinned_toolchain" || "$pinned_toolchain" == *$'\n'* ]]; then
    echo "error: cannot read the single pinned Rust toolchain" >&2; exit 1
fi
export RUSTUP_TOOLCHAIN="$pinned_toolchain"
sdk_path="$(xcrun --sdk "$platform" --show-sdk-path)"
clang_path="$(xcrun --sdk "$platform" --find clang)"
export SDKROOT="$sdk_path"
# Match the existing Swift SQLite connection/provider. Do not link a second
# bundled SQLite or resolve a Homebrew SDK via pkg-config.
export SQLITE3_LIB_DIR="$sdk_path/usr/lib"
export SQLITE3_INCLUDE_DIR="$sdk_path/usr/include"
export SQLITE3_STATIC=0
export SQLITE3_NO_PKG_CONFIG=1
if [[ "$platform" != macosx ]]; then
    : "${IPHONEOS_DEPLOYMENT_TARGET:=17.0}"
    export IPHONEOS_DEPLOYMENT_TARGET
fi
cargo_args=(build --lib --release --locked --no-default-features --target-dir "$output_dir/target")
case "${KEYKEY_GUANYINMA_OFFLINE:-0}" in
    0) ;;
    1) cargo_args+=(--offline) ;;
    *) echo "error: KEYKEY_GUANYINMA_OFFLINE must be 0 or 1" >&2; exit 1 ;;
esac
cd "$core_dir"
archives=()
for architecture in $ARCHS; do
    case "$platform/$architecture" in
        iphoneos/arm64) rust_target=aarch64-apple-ios ;;
        iphonesimulator/arm64) rust_target=aarch64-apple-ios-sim ;;
        iphonesimulator/x86_64) rust_target=x86_64-apple-ios ;;
        macosx/arm64) rust_target=aarch64-apple-darwin ;;
        macosx/x86_64) rust_target=x86_64-apple-darwin ;;
        *) echo "error: unsupported Guanyinma Apple platform/architecture: $platform/$architecture" >&2; exit 1 ;;
    esac
    target_key="$(printf '%s' "$rust_target" | tr '[:lower:]-' '[:upper:]_')"
    export "CARGO_TARGET_${target_key}_LINKER=$clang_path"
    "$cargo_bin" "${cargo_args[@]}" --target "$rust_target"
    archives+=("$output_dir/target/$rust_target/release/libguanyinma.a")
done
if [[ ${#archives[@]} -eq 0 ]]; then
    echo "error: ARCHS must include at least one supported architecture" >&2; exit 1
fi
# Both native targets depend on one aggregate build. Keep the final archive's
# timestamp if unchanged, and never publish a partial file to either linker.
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
printf 'Guanyinma archive: %s\n' "$output_dir/libguanyinma.a"
