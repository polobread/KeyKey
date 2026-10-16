#!/bin/bash
set -euo pipefail

APP=${1:-../Source/build/Release/chichi77 KeyKey.app}
VERSION=$(/usr/bin/plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Library/Input Methods"
cp -R "$APP" "$STAGE/Library/Input Methods/"

STAGED="$STAGE/Library/Input Methods/$(basename "$APP")"

# The standalone TIS tool does not start IMK or load the user's database.
# macOS releases support Apple Silicon only; reject a mismatched payload.
# Sign the standalone helper with the rest of the app below.
executable=$(/usr/bin/plutil -extract CFBundleExecutable raw "$STAGED/Contents/Info.plist")
payload_arch=$(/usr/bin/lipo -archs "$STAGED/Contents/MacOS/$executable")
if [[ "$payload_arch" != "arm64" ]]; then
    echo "macOS packaging requires an arm64-only app; found: $payload_arch" >&2
    exit 1
fi
xcrun clang -fno-objc-arc -mmacosx-version-min=15.0 -arch arm64 \
    -framework Cocoa -framework Carbon InputSourceTool.m \
    -o "$STAGED/Contents/MacOS/KeyKeyInputSourceTool"

# The framework targets sign their own output while Headers is still populated,
# then the app's Copy Files phase strips it, so the seal keeps listing files
# that are no longer there and every --deep --strict verify reports "a sealed
# resource is missing or invalid". Notarisation rejects that. Headers are of no
# use at runtime, so drop them before anything signs or seals the bundle.
for f in "$STAGED"/Contents/Frameworks/*.framework; do
    # Preserve Sparkle's vendor-signed resources and helper entitlements.
    [[ "$(basename "$f")" == "Sparkle.framework" ]] && continue
    rm -rf "$f/Versions/A/Headers" "$f/Headers"
done

SIGN_IDENTITY=${DEVELOPER_ID_APPLICATION:--}
if [ "$SIGN_IDENTITY" == "-" ]; then
    echo "DEVELOPER_ID_APPLICATION is not set, signing the local app ad hoc" >&2
fi

# Removing framework headers invalidates the original build signatures. Sign
# nested code first, then the app, even for an unsigned local test package.
python3 ../update/sign-macos.py "$STAGED" "$SIGN_IDENTITY"

# pkgbuild marks app bundles relocatable by default, which lets installer
# redirect the payload onto any copy of the same bundle id it can find --
# a build directory, a copy in Downloads -- and report success while
# /Library/Input Methods is left untouched. An input method only works from
# the path Text Input Services scans, so pin it.
COMPONENTS="$STAGE.plist"
SCRIPTS="$STAGE-scripts"
trap 'rm -rf "$STAGE" "$COMPONENTS" "$SCRIPTS"' EXIT
mkdir -p "$SCRIPTS"
cp Scripts/preinstall Scripts/postinstall "$SCRIPTS/"
chmod 755 "$SCRIPTS/preinstall" "$SCRIPTS/postinstall"
cp "$STAGED/Contents/MacOS/KeyKeyInputSourceTool" "$SCRIPTS/KeyKeyInputSourceTool"
pkgbuild --analyze --root "$STAGE" "$COMPONENTS"
# Sparkle adds nested bundles; index 0 is not necessarily the IMK app.
# Write every component's relocation policy together and fail on a write error.
python3 - "$COMPONENTS" <<'PY'
from pathlib import Path
import plistlib
import sys

path = Path(sys.argv[1])
components = plistlib.loads(path.read_bytes())
if not isinstance(components, list) or not components:
    raise ValueError("pkgbuild returned no bundle components")
for component in components:
    component["BundleIsRelocatable"] = False
path.write_bytes(plistlib.dumps(components))
PY

pkgbuild \
    --root "$STAGE" \
    --component-plist "$COMPONENTS" \
    --identifier io.github.polobread.chichi77.installerpackage \
    --version "$VERSION" \
    --ownership recommended \
    --scripts "$SCRIPTS" \
    chichi77KeyKeyApp.pkg

if [ -n "${DEVELOPER_ID_INSTALLER:-}" ]; then
    productbuild \
        --sign "$DEVELOPER_ID_INSTALLER" \
        --distribution distribution.plist \
        --resources ./Resources \
        --package-path chichi77KeyKeyApp.pkg \
        chichi77KeyKey.pkg
else
    echo "DEVELOPER_ID_INSTALLER is not set, building an unsigned package" >&2
    productbuild \
        --distribution distribution.plist \
        --resources ./Resources \
        --package-path chichi77KeyKeyApp.pkg \
        chichi77KeyKey.pkg
fi

rm -f chichi77KeyKeyApp.pkg

if [ -n "${NOTARY_PROFILE:-}" ]; then
    notary_args=(--profile "$NOTARY_PROFILE" --out "${NOTARY_LOG_DIR:-notarization-logs}")
    if [ -n "${KEYCHAIN:-}" ]; then
        notary_args+=(--keychain "$KEYCHAIN")
    fi
    python3 ../update/notarize-macos.py chichi77KeyKey.pkg "${notary_args[@]}"
fi

rm -f chichi77KeyKey.pkg.zip
ditto -c -k --sequesterRsrc chichi77KeyKey.pkg chichi77KeyKey.pkg.zip
