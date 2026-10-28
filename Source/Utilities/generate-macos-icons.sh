#!/bin/bash
# Generate macOS ICNS from the existing brand artwork, with native small/Retina
# encodings. Windows ICO generation stays in generate-brand-icons.ps1.
# Usage: bash Source/Utilities/generate-macos-icons.sh [source.png] [output-dir]
set -euo pipefail

task_root=$(cd "$(dirname "$0")/../.." && pwd)
task_source=${1:-"$task_root/Source/Branding/chichi77.png"}
task_output=${2:-"$task_root/Source/Loaders/OSX-IMK/Images"}
task_temp=$(mktemp -d)
trap 'rm -rf "$task_temp"' EXIT

test -f "$task_source"
mkdir -p "$task_output" "$task_temp/app.iconset" \
    "$task_temp/menu16.iconset" "$task_temp/menu32.iconset"

# Give iconutil the logical size and scale, rather than hand-writing PNG chunks
# that macOS may interpret as legacy small-icon pixel data.
for task_size in 16 32 128 256 512; do
    for task_scale in 1 2; do
        # Use the PNG Retina representation for small logical sizes. On current
        # macOS the legacy 1x ARGB representation can decode with corrupt pixels;
        # Icon Services scales the matching 2x PNG for non-Retina displays too.
        if [[ "$task_scale" == 1 && "$task_size" -lt 128 ]]; then continue; fi
        task_suffix=""
        if [[ "$task_scale" == 2 ]]; then task_suffix="@2x"; fi
        task_pixels=$((task_size * task_scale))
        /usr/bin/sips -z "$task_pixels" "$task_pixels" "$task_source" \
            --out "$task_temp/app.iconset/icon_${task_size}x${task_size}${task_suffix}.png" >/dev/null
    done
done

cp "$task_temp/app.iconset/icon_16x16"*.png "$task_temp/menu16.iconset/"
cp "$task_temp/app.iconset/icon_32x32"*.png "$task_temp/menu32.iconset/"
/usr/bin/iconutil -c icns -o "$task_output/chichi77.icns" "$task_temp/app.iconset"
/usr/bin/iconutil -c icns -o "$task_output/chichi7716.icns" "$task_temp/menu16.iconset"
/usr/bin/iconutil -c icns -o "$task_output/chichi7732.icns" "$task_temp/menu32.iconset"
