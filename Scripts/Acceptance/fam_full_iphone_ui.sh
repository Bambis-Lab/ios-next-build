#!/usr/bin/env bash
set -euo pipefail
# FINAL family branch mandatory iPhone-only G99 regression. No release, no merge, no iPad, no live Factory.
test "$GITHUB_REF_NAME" = "feature/iosnext-171-family-bootstrap"
test "$(git rev-parse HEAD)" = "$GITHUB_SHA"
xcrun --sdk iphonesimulator --show-sdk-version | grep -E "^27\\.[0-9]+"
if ! command -v xcodegen >/dev/null 2>&1; then HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen; fi
xcodegen generate --spec project.yml --project .
mkdir -p build/g99/attachments
SIM_ID="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; a=[x["udid"] for k,v in d.items() if "iOS-27" in k for x in v if x.get("isAvailable",True) and x["name"]=="iPhone 18 Pro Max"]; assert len(a)==1, "exact iPhone 18 Pro Max / iOS 27 required"; print(a[0])')"
export SIM_ID
IOSNEXT_BOOTSTATUS_TIMEOUT_SECONDS=210 python3 Scripts/Acceptance/boot_simulator.py "iPhone 18 Pro Max" "iOS-27-0" 2>&1 | tee build/g99/boot.log
xcrun simctl ui "$SIM_ID" appearance light
printf 'sha=%s\nbranch=%s\nsim=%s\nruntime=iOS27\norientation=portrait\n' "$GITHUB_SHA" "$GITHUB_REF_NAME" "$SIM_ID" > build/g99/environment.txt

xcodebuild build-for-testing -collect-test-diagnostics never \
  -project IOSNext.xcodeproj -scheme IOSNext -configuration Debug -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$SIM_ID" -parallel-testing-enabled NO \
  -derivedDataPath build/g99/DerivedData \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY="-" \
  2>&1 | tee build/g99/BuildForTesting.log
APP="build/g99/DerivedData/Build/Products/Debug-iphonesimulator/IOSNext.app"
XCTESTRUN_PATH="$(find build/g99/DerivedData/Build/Products -maxdepth 1 -type f -name '*.xctestrun' -print -quit)"
test -d "$APP" && test -n "$XCTESTRUN_PATH"
xcrun simctl install "$SIM_ID" "$APP"
xcrun simctl launch --terminate-running-process "$SIM_ID" de.nicofroeba16.iosnext --product-ui-test-screen=home 2>&1 | tee build/g99/prewarm.log
sleep 2
xcrun simctl terminate "$SIM_ID" de.nicofroeba16.iosnext || true

# G99-FIX-01/02: isolate first-launch instability (paired with FIX-03 fixtures) before the product UI matrix.
# Only a diagnosed XCTest app-process launch failure may receive ONE retry.
# Store both attempts, including any failure, for auditable evidence.
STARTUP_DIR="build/g99/attachments/startup"
mkdir -p "$STARTUP_DIR"
run_startup_probe() {
  local name="$1"
  local status=0
  set +e
  xcodebuild test-without-building -collect-test-diagnostics never \
    -xctestrun "$XCTESTRUN_PATH" -destination "platform=iOS Simulator,id=$SIM_ID" \
    -parallel-testing-enabled NO -disable-concurrent-destination-testing \
    -resultBundlePath "$STARTUP_DIR/$name.xcresult" \
    "-only-testing:IOSNextUITests/IOSNextUITests/testAccessibilityCoreScreenRenders" \
    CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY="-" \
    2>&1 | tee "$STARTUP_DIR/$name.log"
  status=${PIPESTATUS[0]}
  set -e
  return "$status"
}
if run_startup_probe "first-launch"; then
  echo "G99_STARTUP_PROBE=PASS retry=0" | tee "$STARTUP_DIR/summary.txt"
else
  if ! grep -Eq "does not have a process ID|Failed to launch|Failed to establish.*automation session|Failed to get.*process ID" "$STARTUP_DIR/first-launch.log"; then
    echo "G99_STARTUP_PROBE=FAIL kind=non-launch no-retry" | tee "$STARTUP_DIR/summary.txt"
    exit 65
  fi
  echo "G99_STARTUP_PROBE=INFRA_LAUNCH_RETRY_COUNT_1" | tee "$STARTUP_DIR/summary.txt"
  xcrun simctl terminate "$SIM_ID" de.nicofroeba16.iosnext || true
  xcrun simctl bootstatus "$SIM_ID" -b >> "$STARTUP_DIR/recovery.log" 2>&1
  xcrun simctl launch --terminate-running-process "$SIM_ID" \
    de.nicofroeba16.iosnext --product-ui-test-screen=home >> "$STARTUP_DIR/recovery.log" 2>&1
  xcrun simctl terminate "$SIM_ID" de.nicofroeba16.iosnext || true
  if run_startup_probe "retry-launch"; then
    echo "G99_STARTUP_PROBE=RECOVERED_AFTER_ONE_RETRY" | tee -a "$STARTUP_DIR/summary.txt"
  else
    echo "G99_STARTUP_PROBE=FAIL retries_exhausted" | tee -a "$STARTUP_DIR/summary.txt"
    exit 65
  fi
fi

# The probe and mandatory matrix are separate Xcode test sessions.
# Terminate the app left behind by the first session, then confirm that the
# SAME booted iPhone simulator is ready. Do not reboot or erase it.
xcrun simctl terminate "$SIM_ID" de.nicofroeba16.iosnext || true
xcrun simctl bootstatus "$SIM_ID" -b > build/g99/post-startup-bootstatus.log 2>&1
echo "G99_POST_STARTUP_CLEAN=PASS"

# Mandatory manifest: ten standard UI tests (including the unverified
# family Home regression) and two independent accessibility tests.
# Validate the exact contract before creating the main test selection.
python3 Scripts/Acceptance/validate_fam_g99_manifest.py
set --
n=0
while IFS= read -r selector || [ -n "$selector" ]; do
  [ -n "$selector" ] || { echo "G99_MANIFEST=FAIL blank entry" >&2; exit 65; }
  n=$((n+1))
  if [ "$n" -le 10 ]; then set -- "$@" "-only-testing:$selector"; fi
done < Scripts/Acceptance/g99_iphone_manifest.txt
if [ "$n" -ne 12 ] || [ "$#" -ne 10 ]; then
  echo "G99_MANIFEST=FAIL expected=12 selected_regular=10 observed=$n" >&2
  exit 65
fi
echo "G99_MANIFEST=PASS total=12 regular=10 accessibility=2"
# A single verified Xcode launch-timeout (not an XCTest assertion) may
# trigger ONE complete matrix retry. Keep both full runs and require all 10
# mandatory selectors to actually PASS on the final run.
run_base_matrix() {
  local suffix="$1" code=0
  shift
  set +e
  xcodebuild test-without-building -collect-test-diagnostics never \
    -xctestrun "$XCTESTRUN_PATH" -destination "platform=iOS Simulator,id=$SIM_ID" \
    -parallel-testing-enabled NO -disable-concurrent-destination-testing \
    -resultBundlePath "build/g99/UI-base${suffix}.xcresult" "$@" \
    CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY="-" \
    2>&1 | tee "build/g99/UI-base${suffix}.log"
  code=${PIPESTATUS[0]}
  set -e
  return "$code"
}
FINAL_UI_RESULT="build/g99/UI-base.xcresult"
FINAL_UI_LOG="build/g99/UI-base.log"
if run_base_matrix "" "$@"; then
  python3 Scripts/Acceptance/check_fam_g99_ui_run.py verify "$FINAL_UI_LOG"
  echo "G99_UI_MATRIX=PASS retry=0"
else
  if ! python3 Scripts/Acceptance/check_fam_g99_ui_run.py classify "$FINAL_UI_LOG"; then
    echo "G99_UI_MATRIX=FAIL reason=functional_or_unknown no_retry"
    exit 65
  fi
  echo "G99_UI_MATRIX=INFRA_RETRY_COUNT_1"
  xcrun simctl terminate "$SIM_ID" de.nicofroeba16.iosnext || true
  xcrun simctl bootstatus "$SIM_ID" -b > build/g99/UI-recovery-bootstatus.log 2>&1
  xcrun simctl launch --terminate-running-process "$SIM_ID" \
    de.nicofroeba16.iosnext --product-ui-test-screen=home > build/g99/UI-recovery-prewarm.log 2>&1
  xcrun simctl terminate "$SIM_ID" de.nicofroeba16.iosnext || true
  FINAL_UI_RESULT="build/g99/UI-base-retry1.xcresult"
  FINAL_UI_LOG="build/g99/UI-base-retry1.log"
  if ! run_base_matrix "-retry1" "$@"; then
    echo "G99_UI_MATRIX=FAIL reason=retry_exhausted"
    exit 65
  fi
  python3 Scripts/Acceptance/check_fam_g99_ui_run.py verify "$FINAL_UI_LOG"
  echo "G99_UI_MATRIX=PASS retry=1"
fi
xcrun xcresulttool export attachments --path "$FINAL_UI_RESULT" --output-path build/g99/attachments/base

# Two required independent tests observe real simulator-supported settings.
# Reduce Motion / Reduce Transparency Settings.app automation remains optional
# and cannot block this personal-app acceptance gate.
BEFORE_SIZE="$(xcrun simctl ui "$SIM_ID" content_size)"
BEFORE_CONTRAST="$(xcrun simctl ui "$SIM_ID" increase_contrast)"
test "$BEFORE_SIZE" != unknown && test "$BEFORE_SIZE" != unsupported
case "$BEFORE_CONTRAST" in enabled|disabled) ;; *) exit 1 ;; esac
restore() {
  xcrun simctl ui "$SIM_ID" content_size "$BEFORE_SIZE" || true
  xcrun simctl ui "$SIM_ID" increase_contrast "$BEFORE_CONTRAST" || true
}
trap restore EXIT
run_a11y() {
  local label="$1" method="$2"
  xcodebuild test-without-building -collect-test-diagnostics never \
    -xctestrun "$XCTESTRUN_PATH" -destination "platform=iOS Simulator,id=$SIM_ID" \
    -parallel-testing-enabled NO -disable-concurrent-destination-testing \
    -resultBundlePath "build/g99/a11y-$label.xcresult" \
    "-only-testing:IOSNextUITests/IOSNextUITests/$method" \
    CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY="-" \
    2>&1 | tee "build/g99/a11y-$label.log"
  xcrun xcresulttool export attachments --path "build/g99/a11y-$label.xcresult" --output-path "build/g99/attachments/$label"
}
xcrun simctl ui "$SIM_ID" content_size accessibility-extra-extra-extra-large
test "$(xcrun simctl ui "$SIM_ID" content_size)" = accessibility-extra-extra-extra-large
run_a11y dynamic-type testDynamicTypeAccessibilityState
xcrun simctl ui "$SIM_ID" content_size "$BEFORE_SIZE"
xcrun simctl ui "$SIM_ID" increase_contrast enabled
test "$(xcrun simctl ui "$SIM_ID" increase_contrast)" = enabled
run_a11y increase-contrast testIncreaseContrastAccessibilityState
xcrun simctl ui "$SIM_ID" increase_contrast "$BEFORE_CONTRAST"
echo "G99_UI_ACCEPTANCE=PASS device=iphone18promax modes=light-and-dark mandatory_accessibility=2 optional_settings_switches=excluded"
