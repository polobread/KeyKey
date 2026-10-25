#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=${CI_PRIMARY_REPOSITORY_PATH:-$(CDPATH= cd -- "$script_dir/../../../.." && pwd)}
cooker_dir="$repository_root/Source/Distributions/Takao/DatabaseCooker"
database_path="$repository_root/Source/Distributions/Takao/CookedDatabase/KeyKey.db"
project_dir="$repository_root/Source/Loaders/iOS-Keyboard"

# Prepare only the committed Rust toolchain/standard libraries. Rustup must
# already be provisioned by the CI environment; this hook never downloads and
# executes a shell installer. Xcode's aggregate target builds the archive later.
core_dir="$repository_root/Source/Guanyinma"
rust_channel=$(sed -nE 's/^[[:space:]]*channel[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$core_dir/rust-toolchain.toml")
if [ -z "$rust_channel" ]; then
    echo "error: Cannot read the pinned Guanyinma Rust toolchain." >&2
    exit 1
fi
if command -v rustup >/dev/null 2>&1; then
    rustup_bin=$(command -v rustup)
elif [ -x "${CARGO_HOME:-$HOME/.cargo}/bin/rustup" ]; then
    rustup_bin="${CARGO_HOME:-$HOME/.cargo}/bin/rustup"
else
    echo "error: Xcode Cloud requires a pre-provisioned rustup for Guanyinma." >&2
    echo "Prepare rustup in the CI environment before this post-clone hook." >&2
    exit 1
fi
"$rustup_bin" toolchain install "$rust_channel" --profile minimal
"$rustup_bin" target add --toolchain "$rust_channel" \
    aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios

echo "Verifying the shared KeyKey.db for the iOS keyboard extension..."

if [ ! -s "$database_path" ]; then
    echo "error: Shared KeyKey.db is missing or empty at $database_path" >&2
    exit 1
fi

python3 "$cooker_dir/verify-smart-mandarin-db.py" "$database_path"

if [ -n "${CI_BUILD_NUMBER:-}" ]; then
    case "$CI_BUILD_NUMBER" in
        *[!0-9]*)
            echo "error: CI_BUILD_NUMBER must contain only digits: $CI_BUILD_NUMBER" >&2
            exit 1
            ;;
    esac

    echo "Setting App and Keyboard build number to $CI_BUILD_NUMBER..."
    (cd "$project_dir" && xcrun agvtool new-version -all "$CI_BUILD_NUMBER")
fi

echo "Xcode Cloud prerequisites are ready."
