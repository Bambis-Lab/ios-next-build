#!/bin/bash
set -euo pipefail

if [ -f UITests/VisualAcceptanceMatrix.json ]; then
  exec bash Scripts/run_phase2_visual_acceptance.sh
fi

PROJECT="IOSNext.xcodeproj"
SCHEME="IOSNext"
IPHONE_NAME="${IPHONE_NAME:-${DEVICE_NAME:-iPhone 18 Pro Max}}"
OUT_DIR="UIAcceptance"

: "${DERIVED_DATA_PATH:?DERIVED_DATA_PATH must point to the current isolated DerivedData}"
test -d "$DERIVED_DATA_PATH"
test_run_args=(-project "$PROJECT" -scheme "$SCHEME" -derivedDataPath "$DERIVED_DATA_PATH")
test_run_source="derived-data:$DERIVED_DATA_PATH"

if [ -n "${XCTESTRUN_PATH:-}" ]; then
  case "$XCTESTRUN_PATH" in
    "$DERIVED_DATA_PATH"/*) ;;
    *)
      echo "XCTESTRUN_PATH escaped current run DerivedData: $XCTESTRUN_PATH" >&2
      exit 1
      ;;
  esac
fi

rm -rf "$OUT_DIR" UITestResults-iPhone.xcresult UITestResults-iPad.xcresult
mkdir -p "$OUT_DIR"

devices_json="$(xcrun simctl list devices available -j)"
iphone_id="$(printf '%s' "$devices_json" | IPHONE_NAME="$IPHONE_NAME" python3 -c 'import json,os,sys; data=json.load(sys.stdin); name=os.environ["IPHONE_NAME"]; print(next(d["udid"] for ds in data["devices"].values() for d in ds if d.get("isAvailable", True) and d["name"] == name))')"
ipad_id="$(printf '%s' "$devices_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(next(d["udid"] for ds in data["devices"].values() for d in ds if d.get("isAvailable", True) and d["name"].startswith("iPad")))')"

test -n "$iphone_id"
test -n "$ipad_id"
iphone_booted=0
ipad_booted=0
{
  printf 'iphone=%s\nipad=%s\n' "$iphone_id" "$ipad_id"
  printf 'test_run_source=%s\n' "$test_run_source"
} | tee "$OUT_DIR/devices.txt"

xcrun simctl help ui 2>&1 | tee "$OUT_DIR/simctl-ui-help.txt"

set_reduce_motion() {
  local device="$1"
  local value="$2"
  xcrun simctl spawn "$device" defaults write com.apple.Accessibility ReduceMotionEnabled -bool "$value"
  xcrun simctl spawn "$device" notifyutil -p com.apple.Accessibility.ReduceMotionStatusDidChange || true
}

set_reduce_transparency() {
  local device="$1"
  local value="$2"
  xcrun simctl spawn "$device" defaults write com.apple.Accessibility ReduceTransparencyEnabled -bool "$value"
  xcrun simctl spawn "$device" notifyutil -p com.apple.Accessibility.ReduceTransparencyStatusDidChange || true
}

reset_accessibility() {
  local device="$1"
  xcrun simctl ui "$device" appearance light
  xcrun simctl ui "$device" content_size large
  xcrun simctl ui "$device" increase_contrast disabled
  set_reduce_motion "$device" false
  set_reduce_transparency "$device" false
}

record_accessibility_state() {
  local device="$1"
  local name="$2"
  {
    echo "appearance=$(xcrun simctl ui "$device" appearance)"
    echo "content_size=$(xcrun simctl ui "$device" content_size)"
    echo "increase_contrast=$(xcrun simctl ui "$device" increase_contrast)"
    echo "reduce_motion=$(xcrun simctl spawn "$device" defaults read com.apple.Accessibility ReduceMotionEnabled)"
    echo "reduce_transparency=$(xcrun simctl spawn "$device" defaults read com.apple.Accessibility ReduceTransparencyEnabled)"
  } | tee "$OUT_DIR/$name-settings.txt"
}

cleanup_accessibility_state() {
  set +e
  if [ "$iphone_booted" -eq 1 ]; then
    xcrun simctl terminate "$iphone_id" de.nicofroeba16.iosnext 2>/dev/null || true
    reset_accessibility "$iphone_id"
  fi
  if [ "$ipad_booted" -eq 1 ]; then
    xcrun simctl terminate "$ipad_id" de.nicofroeba16.iosnext 2>/dev/null || true
    reset_accessibility "$ipad_id"
  fi
}
trap cleanup_accessibility_state EXIT

run_accessibility_variant() {
  local name="$1"
  local test_name="$2"
  shift 2

  reset_accessibility "$iphone_id"
  "$@"
  record_accessibility_state "$iphone_id" "$name"

  xcrun simctl terminate "$iphone_id" de.nicofroeba16.iosnext 2>/dev/null || true
  rm -rf "$OUT_DIR/$name.xcresult"
  xcodebuild test-without-building \
    "${test_run_args[@]}" \
    -destination "platform=iOS Simulator,id=$iphone_id" \
    "-only-testing:IOSNextUITests/IOSNextUITests/$test_name" \
    -resultBundlePath "$OUT_DIR/$name.xcresult" \
    | tee -a xcodebuild.log
}

xcrun simctl boot "$iphone_id" 2>/dev/null || true
xcrun simctl bootstatus "$iphone_id" -b
iphone_booted=1
reset_accessibility "$iphone_id"
xcrun simctl terminate "$iphone_id" de.nicofroeba16.iosnext 2>/dev/null || true

xcodebuild test-without-building \
  "${test_run_args[@]}" \
  -destination "platform=iOS Simulator,id=$iphone_id" \
  -only-testing:IOSNextUITests \
  -skip-testing:IOSNextUITests/IOSNextUITests/testIPadPortraitLandscapeCoreScreens \
  -skip-testing:IOSNextUITests/IOSNextUITests/testAccessibilityCoreScreenRenders \
  -skip-testing:IOSNextUITests/IOSNextUITests/testDynamicTypeAccessibilityState \
  -skip-testing:IOSNextUITests/IOSNextUITests/testReduceMotionAccessibilityState \
  -skip-testing:IOSNextUITests/IOSNextUITests/testReduceTransparencyAccessibilityState \
  -skip-testing:IOSNextUITests/IOSNextUITests/testIncreaseContrastAccessibilityState \
  -resultBundlePath UITestResults-iPhone.xcresult \
  | tee -a xcodebuild.log

run_accessibility_variant dynamic-type-xxxl testDynamicTypeAccessibilityState \
  xcrun simctl ui "$iphone_id" content_size accessibility-extra-extra-extra-large
run_accessibility_variant reduce-motion testReduceMotionAccessibilityState \
  set_reduce_motion "$iphone_id" true
run_accessibility_variant reduce-transparency testReduceTransparencyAccessibilityState \
  set_reduce_transparency "$iphone_id" true
run_accessibility_variant increase-contrast testIncreaseContrastAccessibilityState \
  xcrun simctl ui "$iphone_id" increase_contrast enabled

reset_accessibility "$iphone_id"

xcrun simctl boot "$ipad_id" 2>/dev/null || true
xcrun simctl bootstatus "$ipad_id" -b
ipad_booted=1
reset_accessibility "$ipad_id"
xcrun simctl terminate "$ipad_id" de.nicofroeba16.iosnext 2>/dev/null || true

xcodebuild test-without-building \
  "${test_run_args[@]}" \
  -destination "platform=iOS Simulator,id=$ipad_id" \
  -only-testing:IOSNextUITests/IOSNextUITests/testPrimaryProductScreensRenderLightAndDark \
  -only-testing:IOSNextUITests/IOSNextUITests/testIPadPortraitLandscapeCoreScreens \
  -resultBundlePath UITestResults-iPad.xcresult \
  | tee -a xcodebuild.log
