#!/bin/sh

set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repository_root=${CI_PRIMARY_REPOSITORY_PATH:-$(CDPATH='' cd -- "$script_dir/../../../.." && pwd)}
cooker_dir="$repository_root/Source/Distributions/Takao/DatabaseCooker"
database_path="$repository_root/Source/Distributions/Takao/CookedDatabase/KeyKey.db"
project_dir="$repository_root/Source/Loaders/iOS-Keyboard"

# Prepare the committed Rust toolchain/standard libraries on fresh Cloud hosts.
# Bootstrap with a versioned, SHA-256-verified official executable when needed;
# Xcode's aggregate target builds the archive later.
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
    rustup_version=1.29.2
    case "$(uname -s)/$(uname -m)" in
        Darwin/arm64)
            rustup_host=aarch64-apple-darwin
            rustup_sha256=f7c7e11eb2e07f006e532a8aaac77b32f4527d305ac386c0c633ca6133d35ca9
            ;;
        Darwin/x86_64)
            rustup_host=x86_64-apple-darwin
            rustup_sha256=b9610730ddeef52765723847866fd1e3540b2bf7d5ab0c324aa143a5edf25ba0
            ;;
        *)
            echo "error: Guanyinma Xcode Cloud bootstrap requires a supported macOS host." >&2
            exit 1
            ;;
    esac
    installer_dir=$(mktemp -d "${TMPDIR:-/tmp}/keykey-rustup.XXXXXX")
    trap 'rm -rf "$installer_dir"' 0
    installer="$installer_dir/rustup-init"
    echo "Preparing official rustup $rustup_version for $rustup_host..."
    curl --proto '=https' --tlsv1.2 --fail --location --retry 3 \
        --output "$installer" \
        "https://static.rust-lang.org/rustup/archive/$rustup_version/$rustup_host/rustup-init"
    printf '%s  %s\n' "$rustup_sha256" "$installer" | shasum -a 256 --check -
    chmod u+x "$installer"
    "$installer" -y --no-modify-path --profile minimal --default-toolchain none
    rustup_bin="${CARGO_HOME:-$HOME/.cargo}/bin/rustup"
fi
"$rustup_bin" toolchain install "$rust_channel" --profile minimal --component rust-src
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
