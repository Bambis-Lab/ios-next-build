#!/usr/bin/env bash
set -euo pipefail
# Manual-only G99 UI gate. No release, no merge, no iPad, no live Factory.
test "$GITHUB_REF_NAME" = "fix/iosnext-164-dashboard-sliders-fix01-05"
test "$(git rev-parse HEAD)" = "$GITHUB_SHA"
test "$(xcrun --sdk iphonesimulator --show-sdk-version)" = "27.0"
if ! command -v xcodegen >/dev/null 2>&1; then HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen; fi
export CM_COMMIT="$(git rev-parse HEAD)" EXPECTED_VERSION=1.6.4 EXPECTED_BUILD=27
bash Scripts/prepare_free_sideload_project.sh
mkdir -p build/g99/attachments
SIM_ID="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; a=[x["udid"] for k,v in d.items() if "iOS-27" in k for x in v if x.get("isAvailable",True) and x["name"]=="iPhone 18 Pro Max"]; assert len(a)==1, "exact iPhone 18 Pro Max / iOS 27 required"; print(a[0])')"
export SIM_ID
python3 Scripts/Acceptance/boot_simulator.py "iPhone 18 Pro Max" "iOS-27-0" 2>&1 | tee build/g99/boot.log
xcrun simctl ui "$SIM_ID" appearance light
printf 'sha=%s\nbranch=%s\nsim=%s\nruntime=iOS27\norientation=portrait\n' "$GITHUB_SHA" "$GITHUB_REF_NAME" "$SIM_ID" > build/g99/environment.txt

xcodebuild build-for-testing -collect-test-diagnostics never \
  -project IOSNext.xcodeproj -scheme IOSNext -configuration Debug -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$SIM_ID" -parallel-testing-enabled NO \
  -derivedDataPath build/g99/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  2>&1 | tee build/g99/BuildForTesting.log
APP="build/g99/DerivedData/Build/Products/Debug-iphonesimulator/IOSNext.app"
XCTESTRUN_PATH="$(find build/g99/DerivedData/Build/Products -maxdepth 1 -type f -name '*.xctestrun' -print -quit)"
test -d "$APP" && test -n "$XCTESTRUN_PATH"
xcrun simctl install "$SIM_ID" "$APP"
xcrun simctl launch --terminate-running-process "$SIM_ID" de.nicofroeba16.iosnext --product-ui-test-screen=home 2>&1 | tee build/g99/prewarm.log
sleep 2
xcrun simctl terminate "$SIM_ID" de.nicofroeba16.iosnext || true

# Manifest is the only base-suite source of selectors: first nine cases;
# appearance assertions render both Light and Dark inside the visual test.
set --
n=0
while IFS= read -r selector; do
  n=$((n+1))
  if [ "$n" -le 9 ]; then set -- "$@" "-only-testing:$selector"; fi
done < Scripts/Acceptance/g99_iphone_manifest.txt
test "$n" -eq 13
xcodebuild test-without-building -collect-test-diagnostics never \
  -xctestrun "$XCTESTRUN_PATH" -destination "platform=iOS Simulator,id=$SIM_ID" \
  -parallel-testing-enabled NO -disable-concurrent-destination-testing \
  -resultBundlePath build/g99/UI-base.xcresult "$@" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  2>&1 | tee build/g99/UI-base.log
xcrun xcresulttool export attachments --path build/g99/UI-base.xcresult --output-path build/g99/attachments/base

# Four additional independent tests observe real simulator/Settings state.
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
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
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
run_a11y reduce-motion testReduceMotionAccessibilityState
run_a11y reduce-transparency testReduceTransparencyAccessibilityState
echo "G99_UI_ACCEPTANCE=PASS device=iphone18promax modes=light-and-dark genuine_accessibility=4"
