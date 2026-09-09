#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$SCRIPT_DIR/KeyKeyiOS.xcodeproj"
SCHEME="chichi77 KeyKey"
MODE="functional"
CONFIGURATION="Debug"
TEST_PLAN="KeyKeyFunctional"

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
  *)
    echo "Usage: $0 [--smoke|--functional|--functional-host|--functional-extension]" >&2
    exit 64
    ;;
esac

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [--smoke|--functional|--functional-host|--functional-extension]" >&2
  exit 64
fi

if [[ -n "${KEYKEY_IOS_TEST_OUTPUT:-}" ]]; then
  OUTPUT_DIR="$KEYKEY_IOS_TEST_OUTPUT"
  mkdir -p "$OUTPUT_DIR"
else
  OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/keykey-ios-simulator-tests.XXXXXX")"
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
  xcrun simctl list devices available | awk -F '[()]' -v target="$target" '
    index($1, target) { print $2; exit }
  '
}

echo "Output: $OUTPUT_DIR"
if [[ "$MODE" != "smoke" ]]; then
  echo "Running KeyKeyEngine unit tests"
  if ! (cd "$SCRIPT_DIR/KeyKeyEngine" && swift test); then
    echo "KeyKeyEngine unit tests failed" >&2
    exit 1
  fi
fi

failures=0
results=()

for name in "${DEVICE_NAMES[@]}"; do
  udid="$(find_udid "$name")"
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
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testHardwareKeyboardEditorHasCopyAndShareActions"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testHardwareKeyboardEditorLandscapeColumns"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/test00KeyboardOptInIsConfigured"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testInputFieldMatrixIsReachable"
    )
  elif [[ "$MODE" == "functional-extension" ]]; then
    test_args+=(
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testKeyboardExtensionModesAndComposition"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testMultiCharacterAssociationsDoNotResizeKeyboard"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testEnterDismissesAssociatedPhrasesBeforeSendingReturn"
      "-only-testing:KeyKeyUITests/KeyKeyUITests/testPortraitAndLandscapeKeepCoreKeysReachable"
    )
  fi

  echo "Testing $name ($udid) [$MODE, $CONFIGURATION, $TEST_PLAN]"
  if xcodebuild test -quiet \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -testPlan "$TEST_PLAN" \
      -configuration "$CONFIGURATION" \
      -destination "platform=iOS Simulator,arch=arm64,id=$udid" \
      -derivedDataPath "$OUTPUT_DIR/DerivedData" \
      -resultBundlePath "$result_bundle" \
      "${test_args[@]}" \
      CODE_SIGNING_ALLOWED=YES; then
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
  echo "Run --functional-extension after selecting 琦琦注音 to exercise the extension."
elif [[ "$MODE" == "functional-extension" ]]; then
  echo
  echo "Extension mode requires 琦琦注音 to be selected on every Simulator."
elif [[ "$MODE" == "smoke" ]]; then
  echo
  echo "Smoke mode validates the Release container UI without Debug-only launch arguments."
fi

exit "$failures"
