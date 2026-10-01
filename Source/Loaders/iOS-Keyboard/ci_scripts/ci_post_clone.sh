#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=${CI_PRIMARY_REPOSITORY_PATH:-$(CDPATH= cd -- "$script_dir/../../../.." && pwd)}
cooker_dir="$repository_root/Source/Distributions/Takao/DatabaseCooker"
database_path="$repository_root/Source/Distributions/Takao/CookedDatabase/KeyKey.db"
project_dir="$repository_root/Source/Loaders/iOS-Keyboard"

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
