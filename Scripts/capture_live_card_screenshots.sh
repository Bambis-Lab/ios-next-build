#!/bin/bash
set -euo pipefail

if [ -f CIEvidence/phase2-visual-acceptance-manifest.json ]; then
  exec python3 Scripts/phase2_results.py --manifest CIEvidence/phase2-visual-acceptance-manifest.json gate --categories card-catalog
fi

DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"
APP_ID="de.nicofroeba16.iosnext"
OUT_DIR="${OUT_DIR:-CardScreenshots}"
current_appearance="light"

device_id="$(DEVICE_NAME="$DEVICE_NAME" xcrun simctl list devices available -j | DEVICE_NAME="$DEVICE_NAME" python3 -c 'import json,os,sys; name=os.environ["DEVICE_NAME"]; data=json.load(sys.stdin); print(next(device["udid"] for devices in data["devices"].values() for device in devices if device.get("isAvailable", True) and device["name"] == name))')"
test -n "$device_id"
xcrun simctl boot "$device_id" 2>/dev/null || true
xcrun simctl bootstatus "$device_id" -b

: "${DERIVED_DATA_PATH:?DERIVED_DATA_PATH is required}"
: "${XCTESTRUN_PATH:?XCTESTRUN_PATH is required}"
test -f "$XCTESTRUN_PATH"
case "$XCTESTRUN_PATH" in
  "$DERIVED_DATA_PATH"/*) ;;
  *)
    echo "XCTESTRUN_PATH is outside current-run DerivedData: $XCTESTRUN_PATH" >&2
    exit 1
    ;;
esac
products_dir="$(dirname "$XCTESTRUN_PATH")"
app_path="$products_dir/Debug-iphonesimulator/IOSNext.app"
test -d "$app_path"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/logs"

set_visual_baseline() {
  local appearance="$1"
  current_appearance="$appearance"
  xcrun simctl ui "$device_id" appearance "$appearance"
  xcrun simctl ui "$device_id" content_size large
  xcrun simctl ui "$device_id" increase_contrast disabled
  xcrun simctl spawn "$device_id" defaults write com.apple.Accessibility ReduceMotionEnabled -bool false
  xcrun simctl spawn "$device_id" defaults write com.apple.Accessibility ReduceTransparencyEnabled -bool false
  xcrun simctl spawn "$device_id" notifyutil -p com.apple.Accessibility.ReduceMotionStatusDidChange || true
  xcrun simctl spawn "$device_id" notifyutil -p com.apple.Accessibility.ReduceTransparencyStatusDidChange || true

  local state=""
  for _ in {1..40}; do
    state="$(xcrun simctl ui "$device_id" appearance 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
    if [[ "$state" == *"$appearance"* ]]; then
      return 0
    fi
    sleep 0.1
  done
  echo "Appearance failed to settle: expected=$appearance actual=$state" >&2
  return 1
}

restart_simulator() {
  xcrun simctl terminate "$device_id" "$APP_ID" 2>/dev/null || true
  xcrun simctl shutdown "$device_id" 2>/dev/null || true
  xcrun simctl boot "$device_id"
  xcrun simctl bootstatus "$device_id" -b
  set_visual_baseline "$current_appearance"
  data_container="$(xcrun simctl get_app_container "$device_id" "$APP_ID" data)"
  test -d "$data_container"
}

xcrun simctl terminate "$device_id" "$APP_ID" 2>/dev/null || true
xcrun simctl uninstall "$device_id" "$APP_ID" 2>/dev/null || true
xcrun simctl install "$device_id" "$app_path"
data_container="$(xcrun simctl get_app_container "$device_id" "$APP_ID" data)"
test -d "$data_container"

capture_validated() {
  local appearance="$1"
  local page="$2"
  local destination="$OUT_DIR/live-ha-card-$appearance-page-$page.png"
  local attempt nonce marker candidate launch_log validation_log

  rm -f "$destination"

  for attempt in 1 2 3 4; do
    nonce="cards-$appearance-$page-$attempt-$(uuidgen | tr '[:upper:]' '[:lower:]')"
    marker="$data_container/tmp/iosnext-live-card-ready-$page-$nonce"
    candidate="$OUT_DIR/logs/$appearance-page-$page-attempt-$attempt.png"
    launch_log="$OUT_DIR/logs/$appearance-page-$page-attempt-$attempt-launch.log"
    validation_log="$OUT_DIR/logs/$appearance-page-$page-attempt-$attempt-validation.log"

    rm -f "$marker" "$candidate" "$launch_log" "$validation_log"
    xcrun simctl terminate "$device_id" "$APP_ID" 2>/dev/null || true

    if xcrun simctl launch "$device_id" "$APP_ID"       --live-card-test-mode       "--live-card-page=$page"       "--visual-ready-nonce=$nonce"       >"$launch_log" 2>&1; then
      ready=0
      for _ in {1..80}; do
        if [ -f "$marker" ]; then
          ready=1
          break
        fi
        sleep 0.1
      done

      if [ "$ready" -eq 1 ]; then
        xcrun simctl io "$device_id" screenshot "$candidate" >/dev/null
        if xcrun swift Scripts/validate_visual_capture.swift "$candidate" >"$validation_log" 2>&1; then
          cp "$candidate" "$destination"
          return 0
        fi
      else
        echo "ready marker timeout: $marker" >"$validation_log"
      fi
    fi

    if [ "$attempt" -eq 2 ]; then
      restart_simulator
    fi
  done

  echo "Unable to produce a stable card capture: appearance=$appearance page=$page" >&2
  return 1
}

for appearance in light dark; do
  set_visual_baseline "$appearance"
  for page in 0 1 2; do
    capture_validated "$appearance" "$page"
  done
done

capture_count="$(find "$OUT_DIR" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')"
test "$capture_count" -eq 6
unique_hashes="$(shasum -a 256 "$OUT_DIR"/*.png | awk '{print $1}' | sort -u | wc -l | tr -d ' ')"
test "$unique_hashes" -eq 6
catalog_types="$(grep -c '^    case ' Sources/Features/LiveHACardTestModeView.swift | tr -d ' ')"
test "$catalog_types" -eq 12

cat > "$OUT_DIR/summary.txt" <<EOF
Live HA Card Catalog
device=$DEVICE_NAME
appearances=light,dark
pages=3
captures=$capture_count
unique_capture_hashes=$unique_hashes
catalog_types=$catalog_types
capture_strategy=nonce-ready-marker-plus-validation
accessibility_state_reset=true
EOF
