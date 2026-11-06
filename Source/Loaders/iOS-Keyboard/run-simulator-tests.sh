#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$SCRIPT_DIR/KeyKeyiOS.xcodeproj"
SCHEME="chichi77 KeyKey"
MODE="functional"
CONFIGURATION="Debug"
TEST_PLAN="KeyKeyFunctional"

usage() {
  cat <<EOF
Usage: $0 [--functional|--smoke|--functional-host|--functional-extension|--duo|--duo-diagnostics|--help]

  --functional            Run the ordinary functional test plan (default).
  --smoke                 Run Release container smoke tests.
  --functional-host       Run Debug container and hardware-editor checks.
  --functional-extension  Run keyboard input, profile switching and rotation regressions.
  --duo                   Run the optional Duo wide-layout plan.
  --duo-diagnostics       Run diagnostics at the device's current pose.
  --help                  Show this help without creating output or running tests.

KEYKEY_IOS_TEST_DEVICE selects one Simulator by its exact name or UDID instead
of the ordinary device matrix. It is required for both Duo modes; prepare the
chosen device's pose before running. Duplicate names require a UDID.
KEYKEY_IOS_TEST_OUTPUT optionally selects the output directory.
EOF
}

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 64
fi

case "${1:-}" in
  ""|--functional)
    ;;
  --smoke)
    MODE="smoke"
    CONFIGURATION="Release"
    TEST_PLAN="KeyKeySmoke"
    ;;
  --host-only|--functional-host)
    MODE="functional-host"
    ;;
  --functional-extension)
    MODE="functional-extension"
    ;;
  --duo)
    MODE="duo"
    TEST_PLAN="KeyKeyDuo"
    ;;
  --duo-diagnostics)
    MODE="duo-diagnostics"
    TEST_PLAN="KeyKeyDuoDiagnostics"
    ;;
  --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac

if [[ "$MODE" == duo* && -z "${KEYKEY_IOS_TEST_DEVICE:-}" ]]; then
  echo "KEYKEY_IOS_TEST_DEVICE must select an exact Simulator name or UDID for --$MODE." >&2
  exit 64
fi

DEVICE_NAMES=(
  "KeyKey iOS 17 iPhone 12"
  "KeyKey iOS 18 iPhone 15"
  "KeyKey iOS 26 iPhone 17 Pro"
  "KeyKey iOS 26 iPhone SE"
  "KeyKey iOS 26 iPad"
)

find_udid() {
  local target="$1"
  xcrun simctl list devices available --json | python3 -c '
import json
import sys

target = sys.argv[1]
devices = [device for group in json.load(sys.stdin)["devices"].values() for device in group]
matches = [device for device in devices
           if device["name"] == target or device["udid"].casefold() == target.casefold()]
if len(matches) > 1:
    print("Ambiguous Simulator name; select a UDID: " + target, file=sys.stderr)
    for device in matches:
        print("  " + device["name"] + " (" + device["udid"] + ")", file=sys.stderr)
    sys.exit(1)
if matches:
    print(matches[0]["udid"])
' "$target"
}

EXPLICIT_DEVICE_UDID=""
if [[ -n "${KEYKEY_IOS_TEST_DEVICE:-}" ]]; then
  if ! EXPLICIT_DEVICE_UDID="$(find_udid "$KEYKEY_IOS_TEST_DEVICE")"; then
    echo "Could not resolve KEYKEY_IOS_TEST_DEVICE." >&2
    exit 64
  fi
  if [[ -z "$EXPLICIT_DEVICE_UDID" ]]; then
    echo "Simulator not found: $KEYKEY_IOS_TEST_DEVICE" >&2
    exit 64
  fi
  DEVICE_NAMES=("$KEYKEY_IOS_TEST_DEVICE")
fi

if [[ -n "${KEYKEY_IOS_TEST_OUTPUT:-}" ]]; then
  OUTPUT_DIR="$KEYKEY_IOS_TEST_OUTPUT"
  mkdir -p "$OUTPUT_DIR"
else
  OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/keykey-ios-simulator-tests.XXXXXX")"
fi

echo "Output: $OUTPUT_DIR"
if [[ "$MODE" != "smoke" ]]; then
  echo "Running KeyKeyEngine unit tests"
  if ! bash "$SCRIPT_DIR/../../Guanyinma/tools/test-ios-swift-package.sh"; then
    echo "KeyKeyEngine unit tests failed" >&2
    exit 1
  fi
fi

failures=0
results=()

for name in "${DEVICE_NAMES[@]}"; do
  if [[ -n "$EXPLICIT_DEVICE_UDID" ]]; then
    udid="$EXPLICIT_DEVICE_UDID"
  elif ! udid="$(find_udid "$name")"; then
    echo "FAIL  $name (Simulator lookup failed)" >&2
    results+=("FAIL|$name|Simulator lookup failed")
    failures=$((failures + 1))
    continue
  fi
  if [[ -z "$udid" ]]; then
    echo "FAIL  $name (Simulator not found)" >&2
    results+=("FAIL|$name|Simulator not found")
    failures=$((failures + 1))
    continue
  fi

  xcrun simctl boot "$udid" 2>/dev/null || true
  if ! xcrun simctl bootstatus "$udid" -b; then
    echo "FAIL  $name (boot failed)" >&2
    results+=("FAIL|$name|boot failed")
    failures=$((failures + 1))
    continue
  fi

  slug="${name// /-}"
  if [[ -n "$EXPLICIT_DEVICE_UDID" ]]; then slug="$udid"; fi
  result_bundle="$OUTPUT_DIR/$slug-$MODE.xcresult"
  test_args=()
  if [[ "$MODE" == "functional-host" ]]; then
    test_args+=(
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testSmokeContainerAppLaunchesWithProductionControls"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testSmokeHardwareKeyboardEditorOpens"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testSmokeContainerAppSurvivesRotationAndRelaunch"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testSmokeSettingsEntryOpensSystemSettings"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testAcknowledgementsAreBundledAndReachable"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testSupporterPurchaseControlsAreReachable"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testHardwareEditorRightHandSelectionSurvivesRotationAndRefocus"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testHardwareEditorForwardDeleteKeepsCompositionAndRemovesLastReading"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testHardwareEditorForwardDeleteRemovesCommittedGraphemes"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testHardwareKeyboardEditorHasCopyAndShareActions"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testHardwareKeyboardEditorLandscapeColumns"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/test00KeyboardOptInIsConfigured"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testInputFieldMatrixIsReachable"
    )
  elif [[ "$MODE" == "functional-extension" ]]; then
    test_args+=(
      "-only-testing:KeyKeyUITests/KeyKeyUITests/test00KeyboardOptInIsConfigured"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testKeyboardExtensionModesAndComposition"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testMultiCharacterAssociationsDoNotResizeKeyboard"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testEnterDismissesAssociatedPhrasesBeforeSendingReturn"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testFullProfilePortraitAndLandscapeKeepDeclaredKeysReachable"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testManualSplitKeyboardPreservesCompositionAndPersists"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testSplitSmartPagingRotationKeepsUnfinishedReading"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testSplitSmartNineTenSyllableBoundaryAndDeletion"
    )
  fi

  echo "Testing $name ($udid) [$MODE, $CONFIGURATION, $TEST_PLAN]"
  test_command=(xcodebuild test -quiet \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -testPlan "$TEST_PLAN" \
      -configuration "$CONFIGURATION" \
      -destination "platform=iOS Simulator,arch=arm64,id=$udid" \
      -derivedDataPath "$OUTPUT_DIR/DerivedData" \
      -resultBundlePath "$result_bundle" \
      "${test_args[@]}" \
      CODE_SIGNING_ALLOWED=YES)
  if [[ "$MODE" == "functional" || "$MODE" == "functional-host" ]]; then
    test_command=(python3 "$SCRIPT_DIR/Tests/with-simulator-hid.py"
      --device "$udid" --output "$OUTPUT_DIR/hid-$udid" -- "${test_command[@]}")
  fi
  if "${test_command[@]}"; then
    skipped_tests=0
    if result_summary="$(xcrun xcresulttool get test-results summary --path "$result_bundle")"; then
      skipped_tests="$(awk '
        /"skippedTests"/ { total += $3 }
        END { print total + 0 }
      ' <<< "$result_summary")"
    else
      skipped_tests=-1
    fi
    if [[ "$skipped_tests" -lt 0 ]]; then
      echo "FAIL  $name (could not inspect skipped-test count)" >&2
      results+=("FAIL|$name|$result_bundle")
      failures=$((failures + 1))
    elif [[ "$skipped_tests" -eq 0 ]]; then
      echo "PASS  $name"
      results+=("PASS|$name|$result_bundle")
    else
      echo "FAIL  $name ($skipped_tests skipped test records; extension was not exercised)" >&2
      results+=("FAIL|$name|$result_bundle")
      failures=$((failures + 1))
    fi
  else
    echo "FAIL  $name" >&2
    results+=("FAIL|$name|$result_bundle")
    failures=$((failures + 1))
  fi
done

echo
echo "Result summary"
for result in "${results[@]}"; do
  IFS='|' read -r status name detail <<< "$result"
  printf '%-4s  %-30s  %s\n' "$status" "$name" "$detail"
done

if [[ "$MODE" == "functional-host" ]]; then
  echo
  echo "Functional host mode validates production smoke, Settings opt-in, acknowledgements,"
  echo "all 14 input-field hosts, and the hardware-keyboard editor."
  echo "Run --functional-extension to exercise keyboard input and profile switching."
elif [[ "$MODE" == "functional-extension" ]]; then
  echo
  echo "Extension mode opts in to 琦琦輸入法, then checks input, profile switching and rotation."
elif [[ "$MODE" == "duo" ]]; then
  echo
  echo "Duo mode validates the selected device's wide split layout; its inner display must be open."
elif [[ "$MODE" == "duo-diagnostics" ]]; then
  echo
  echo "Duo diagnostics preserve the selected device's current pose."
  echo "The native keyboard comparison also requires the system Zhuyin keyboard to be enabled."
elif [[ "$MODE" == "smoke" ]]; then
  echo
  echo "Smoke mode validates the Release container UI without Debug-only launch arguments."
fi

exit "$failures"
