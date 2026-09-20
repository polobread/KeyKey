#!/bin/bash
set -euo pipefail

APP=${1:-../Source/build/Release/chichi77 KeyKey.app}
VERSION=$(/usr/bin/plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Library/Input Methods"
cp -R "$APP" "$STAGE/Library/Input Methods/"

STAGED="$STAGE/Library/Input Methods/$(basename "$APP")"

# The framework targets sign their own output while Headers is still populated,
# then the app's Copy Files phase strips it, so the seal keeps listing files
# that are no longer there and every --deep --strict verify reports "a sealed
# resource is missing or invalid". Notarisation rejects that. Headers are of no
# use at runtime, so drop them before anything signs or seals the bundle.
for f in "$STAGED"/Contents/Frameworks/*.framework; do
    rm -rf "$f/Versions/A/Headers" "$f/Headers"
done

SIGN_IDENTITY=${DEVELOPER_ID_APPLICATION:--}
if [ "$SIGN_IDENTITY" != "-" ]; then
    # Developer ID packages need Hardened Runtime and a secure timestamp.
    sign_staged() {
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$1"
    }
else
    echo "DEVELOPER_ID_APPLICATION is not set, signing the local app ad hoc" >&2
    sign_staged() {
        codesign --force --sign - "$1"
    }
fi

# Removing framework headers invalidates the original build signatures. Sign
# nested code first, then the app, even for an unsigned local test package.
for f in "$STAGED"/Contents/Frameworks/*.framework; do
    sign_staged "$f"
done

for f in "$STAGED"/Contents/SharedSupport/*.app; do
    sign_staged "$f"
done

sign_staged "$STAGED"
codesign --verify --deep --strict --verbose=2 "$STAGED"

# pkgbuild marks app bundles relocatable by default, which lets installer
# redirect the payload onto any copy of the same bundle id it can find --
# a build directory, a copy in Downloads -- and report success while
# /Library/Input Methods is left untouched. An input method only works from
# the path Text Input Services scans, so pin it.
COMPONENTS="$STAGE.plist"
trap 'rm -rf "$STAGE" "$COMPONENTS"' EXIT
pkgbuild --analyze --root "$STAGE" "$COMPONENTS"
if ! /usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$COMPONENTS" 2>/dev/null; then
    # Recent pkgbuild versions may omit the key instead of emitting its default.
    /usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$COMPONENTS"
fi

pkgbuild \
    --root "$STAGE" \
    --component-plist "$COMPONENTS" \
    --identifier io.github.polobread.chichi77.installerpackage \
    --version "$VERSION" \
    --ownership recommended \
    --scripts Scripts \
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
    xcrun notarytool submit chichi77KeyKey.pkg --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple chichi77KeyKey.pkg
fi

rm -f chichi77KeyKey.pkg.zip
ditto -c -k --sequesterRsrc chichi77KeyKey.pkg chichi77KeyKey.pkg.zip
