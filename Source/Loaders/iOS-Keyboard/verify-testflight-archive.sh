#!/usr/bin/env bash

set -euo pipefail

EXPECTED_APP_ID="io.github.polobread.inputmethod.chichi77.ios"
EXPECTED_EXTENSION_ID="io.github.polobread.inputmethod.chichi77.ios.keyboard"
EXPECTED_APP_GROUP="group.io.github.polobread.inputmethod.chichi77.ios"
ALLOW_UNSIGNED_SIMULATOR=0
INPUT_PATH=""

usage() {
  echo "Usage: $0 [--allow-unsigned-simulator] <path-to-xcarchive-or-app>" >&2
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-unsigned-simulator)
      ALLOW_UNSIGNED_SIMULATOR=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      usage
      fail "Unknown option: $1"
      ;;
    *)
      [[ -z "$INPUT_PATH" ]] || fail "Only one archive or app path is allowed"
      INPUT_PATH="$1"
      ;;
  esac
  shift
done

[[ -n "$INPUT_PATH" ]] || { usage; exit 64; }
[[ -e "$INPUT_PATH" ]] || fail "Path does not exist: $INPUT_PATH"

if [[ "$INPUT_PATH" == *.xcarchive ]]; then
  applications="$INPUT_PATH/Products/Applications"
  [[ -d "$applications" ]] || fail "Archive has no Products/Applications directory"
  app_candidates=("$applications"/*.app)
  [[ ${#app_candidates[@]} -eq 1 && -d "${app_candidates[0]}" ]] \
    || fail "Archive must contain exactly one application"
  APP_PATH="${app_candidates[0]}"
elif [[ "$INPUT_PATH" == *.app && -d "$INPUT_PATH" ]]; then
  APP_PATH="$INPUT_PATH"
else
  usage
  fail "Expected an .xcarchive or .app directory"
fi

EXTENSION_PATH="$APP_PATH/PlugIns/Keyboard.appex"
APP_INFO="$APP_PATH/Info.plist"
EXTENSION_INFO="$EXTENSION_PATH/Info.plist"
DATABASE_PATH="$EXTENSION_PATH/KeyKey.db"

[[ -f "$APP_INFO" ]] || fail "Container Info.plist is missing"
[[ -d "$EXTENSION_PATH" ]] || fail "Keyboard.appex is missing"
[[ -f "$EXTENSION_INFO" ]] || fail "Keyboard extension Info.plist is missing"
[[ -s "$DATABASE_PATH" ]] || fail "Keyboard.appex/KeyKey.db is missing or empty"
pass "container app, keyboard extension, and database are present"

database_count="$(find "$APP_PATH" -type f -name KeyKey.db | wc -l | tr -d '[:space:]')"
[[ "$database_count" == "1" ]] || fail "Expected one KeyKey.db, found $database_count"
pass "KeyKey.db is packaged exactly once"

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

app_identifier="$(plist_value "$APP_INFO" CFBundleIdentifier)"
extension_identifier="$(plist_value "$EXTENSION_INFO" CFBundleIdentifier)"
[[ "$app_identifier" == "$EXPECTED_APP_ID" ]] \
  || fail "Unexpected app identifier: $app_identifier"
[[ "$extension_identifier" == "$EXPECTED_EXTENSION_ID" ]] \
  || fail "Unexpected extension identifier: $extension_identifier"
pass "bundle identifiers match production"

app_version="$(plist_value "$APP_INFO" CFBundleShortVersionString)"
extension_version="$(plist_value "$EXTENSION_INFO" CFBundleShortVersionString)"
app_build="$(plist_value "$APP_INFO" CFBundleVersion)"
extension_build="$(plist_value "$EXTENSION_INFO" CFBundleVersion)"
[[ -n "$app_version" && "$app_version" == "$extension_version" ]] \
  || fail "Marketing versions differ: app=$app_version extension=$extension_version"
[[ -n "$app_build" && "$app_build" == "$extension_build" ]] \
  || fail "Build numbers differ: app=$app_build extension=$extension_build"
pass "container and extension versions match ($app_version ($app_build))"

open_access="$(plist_value "$EXTENSION_INFO" NSExtension:NSExtensionAttributes:RequestsOpenAccess)"
[[ "$open_access" == "false" ]] || fail "RequestsOpenAccess must be false, got $open_access"
pass "keyboard does not request Full Access"

[[ -f "$APP_PATH/PrivacyInfo.xcprivacy" ]] || fail "Container PrivacyInfo.xcprivacy is missing"
[[ -f "$EXTENSION_PATH/PrivacyInfo.xcprivacy" ]] \
  || fail "Keyboard PrivacyInfo.xcprivacy is missing"
pass "both privacy manifests are packaged"

app_executable="$(plist_value "$APP_INFO" CFBundleExecutable)"
app_binary="$APP_PATH/$app_executable"
[[ -x "$app_binary" ]] || fail "Container executable is missing: $app_executable"
if grep -a -F -q "open-input-field-test" "$app_binary"; then
  fail "Release app contains the Debug-only input-field test entry"
fi
pass "Debug-only input-field entry is absent"

if [[ "$ALLOW_UNSIGNED_SIMULATOR" -eq 1 ]]; then
  platform_name="$(plist_value "$APP_INFO" DTPlatformName || true)"
  [[ "$platform_name" == "iphonesimulator" ]] \
    || fail "--allow-unsigned-simulator requires an iPhone Simulator build"
  if codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
    pass "Simulator app signature is internally consistent"
  else
    echo "SKIP: distribution signature and entitlements (unsigned Simulator build)"
  fi
else
  codesign --verify --deep --strict "$APP_PATH" \
    || fail "Container or embedded extension signature is invalid"
  pass "distribution signatures are valid"

  temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/keykey-entitlements.XXXXXX")"
  trap 'rm -rf "$temporary_dir"' EXIT

  verify_entitlements() {
    local bundle_path="$1"
    local label="$2"
    local output="$temporary_dir/$label.plist"
    codesign -d --entitlements :- "$bundle_path" >"$output" 2>/dev/null \
      || fail "Could not read $label entitlements"

    local groups
    groups="$(/usr/libexec/PlistBuddy \
      -c 'Print :com.apple.security.application-groups' "$output" 2>/dev/null)" \
      || fail "$label has no App Group entitlement"
    grep -F -q "$EXPECTED_APP_GROUP" <<<"$groups" \
      || fail "$label does not contain the production App Group"

    local get_task_allow
    if get_task_allow="$(/usr/libexec/PlistBuddy \
      -c 'Print :get-task-allow' "$output" 2>/dev/null)"; then
      [[ "$get_task_allow" == "false" ]] \
        || fail "$label distribution entitlement has get-task-allow=$get_task_allow"
    fi
  }

  verify_entitlements "$APP_PATH" app
  verify_entitlements "$EXTENSION_PATH" extension
  pass "production App Group is signed into both targets and get-task-allow is disabled"
fi

echo "Archive verification passed: $APP_PATH"
