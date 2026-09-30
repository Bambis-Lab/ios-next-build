#!/bin/bash
set -euo pipefail

if [ -f CIEvidence/phase2-visual-acceptance-manifest.json ]; then
  exec python3 Scripts/phase2_results.py --manifest CIEvidence/phase2-visual-acceptance-manifest.json gate --categories cold-launch,state,primary-screen,navigation,detail,safe-state,interaction,accessibility,orientation
fi

DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"
APP_ID="de.nicofroeba16.iosnext"
OUT_DIR="${OUT_DIR:-DarkVisualAcceptance}"
MAX_CAPTURE_ATTEMPTS="${MAX_CAPTURE_ATTEMPTS:-4}"
record_pid=""

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
mkdir -p "$OUT_DIR/product-screens" "$OUT_DIR/logs"

stop_recording() {
  if [ -n "$record_pid" ]; then
    kill -INT "$record_pid" 2>/dev/null || true
    wait "$record_pid" 2>/dev/null || true
    record_pid=""
  fi
}
trap stop_recording EXIT

set_visual_baseline() {
  xcrun simctl ui "$device_id" appearance dark
  xcrun simctl ui "$device_id" content_size large
  xcrun simctl ui "$device_id" increase_contrast disabled
  xcrun simctl spawn "$device_id" defaults write com.apple.Accessibility ReduceMotionEnabled -bool false
  xcrun simctl spawn "$device_id" defaults write com.apple.Accessibility ReduceTransparencyEnabled -bool false
  xcrun simctl spawn "$device_id" notifyutil -p com.apple.Accessibility.ReduceMotionStatusDidChange || true
  xcrun simctl spawn "$device_id" notifyutil -p com.apple.Accessibility.ReduceTransparencyStatusDidChange || true

  local state=""
  for _ in {1..40}; do
    state="$(xcrun simctl ui "$device_id" appearance 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
    if [[ "$state" == *dark* ]]; then
      return 0
    fi
    sleep 0.1
  done
  echo "Dark appearance failed to settle: $state" >&2
  return 1
}

restart_simulator() {
  stop_recording
  xcrun simctl terminate "$device_id" "$APP_ID" 2>/dev/null || true
  xcrun simctl shutdown "$device_id" 2>/dev/null || true
  xcrun simctl boot "$device_id"
  xcrun simctl bootstatus "$device_id" -b
  set_visual_baseline
  data_container="$(xcrun simctl get_app_container "$device_id" "$APP_ID" data)"
  test -d "$data_container"
}

set_visual_baseline
xcrun simctl terminate "$device_id" "$APP_ID" 2>/dev/null || true
xcrun simctl uninstall "$device_id" "$APP_ID" 2>/dev/null || true
xcrun simctl install "$device_id" "$app_path"
data_container="$(xcrun simctl get_app_container "$device_id" "$APP_ID" data)"
test -d "$data_container"

capture_product_screen() {
  local screen="$1"
  local destination="$OUT_DIR/product-screens/$screen.png"
  local attempt nonce marker candidate validation_log launch_log

  rm -f "$destination"

  for attempt in $(seq 1 "$MAX_CAPTURE_ATTEMPTS"); do
    nonce="dark-$screen-$attempt-$(uuidgen | tr '[:upper:]' '[:lower:]')"
    marker="$data_container/tmp/iosnext-product-screen-ready-$screen-dark-$nonce"
    candidate="$OUT_DIR/logs/$screen-attempt-$attempt.png"
    validation_log="$OUT_DIR/logs/$screen-attempt-$attempt-validation.log"
    launch_log="$OUT_DIR/logs/$screen-attempt-$attempt-launch.log"

    rm -f "$candidate" "$marker" "$validation_log" "$launch_log"
    xcrun simctl terminate "$device_id" "$APP_ID" 2>/dev/null || true

    if ! xcrun simctl launch "$device_id" "$APP_ID"       "--product-ui-test-screen=$screen"       --product-ui-test-dark       "--visual-ready-nonce=$nonce"       >"$launch_log" 2>&1; then
      echo "Launch failed for $screen attempt $attempt" >>"$launch_log"
    else
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

  echo "Unable to capture stable Dark Mode screen: $screen" >&2
  return 1
}

for screen in home rooms chat media system light media-detail owner wireguard; do
  capture_product_screen "$screen"
done

record_cold_launch() {
  local video="$OUT_DIR/cold-launch-dark.mp4"
  local attempt bytes validation_log

  for attempt in 1 2 3; do
    validation_log="$OUT_DIR/logs/cold-launch-attempt-$attempt-validation.log"
    rm -f "$video" "$validation_log"
    xcrun simctl terminate "$device_id" "$APP_ID" 2>/dev/null || true

    xcrun simctl io "$device_id" recordVideo --codec=h264 "$video"       >"$OUT_DIR/logs/cold-launch-attempt-$attempt-record.log" 2>&1 &
    record_pid=$!
    sleep 0.35

    if ! xcrun simctl launch "$device_id" "$APP_ID"       >"$OUT_DIR/logs/cold-launch-attempt-$attempt-launch.log" 2>&1; then
      stop_recording
      continue
    fi

    sleep 6
    stop_recording

    if [ -s "$video" ]; then
      bytes="$(stat -f%z "$video")"
      if [ "$bytes" -gt 50000 ]         && xcrun swift Scripts/validate_visual_video.swift "$video" cold >"$validation_log" 2>&1; then
        echo "$bytes"
        return 0
      fi
    fi

    if [ "$attempt" -eq 2 ]; then
      restart_simulator
    fi
  done

  echo "Unable to record a valid cold-launch video" >&2
  return 1
}

cold_bytes="$(record_cold_launch)"

screen_count="$(find "$OUT_DIR/product-screens" -name '*.png' | wc -l | tr -d ' ')"
test "$screen_count" -eq 9
unique_screen_hashes="$(shasum -a 256 "$OUT_DIR"/product-screens/*.png | awk '{print $1}' | sort -u | wc -l | tr -d ' ')"
test "$unique_screen_hashes" -eq 9

cat > "$OUT_DIR/summary.txt" <<EOF
iOS Next Dark Visual Acceptance
device=$DEVICE_NAME
appearance=dark
content_size=large
increase_contrast=disabled
reduce_motion=false
reduce_transparency=false
product_screens=$screen_count
unique_product_screen_hashes=$unique_screen_hashes
cold_launch_video_bytes=$cold_bytes
cold_launch_frame_validation=true
normal_launch_has_test_arguments=false
product_capture_uses_nonce_ready_marker=true
product_capture_validates_each_attempt=true
simulator_restart_after_repeated_capture_failure=true
interaction_animation_recorded_here=false
EOF
