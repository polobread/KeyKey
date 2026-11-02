#!/usr/bin/env bash
# Prepare Apple's native CJK font before headless AppKit tests and ibtool.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
font_build="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/keykey-fonts.XXXXXX")"
trap 'rm -rf -- "$font_build"' EXIT
xcrun clang -fobjc-arc -fblocks -framework Foundation -framework CoreText \
  "$script_dir/prepare-macos-test-fonts.m" -o "$font_build/prepare-font"
"$font_build/prepare-font" "$@"
