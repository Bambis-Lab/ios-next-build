#!/bin/bash
set -euo pipefail

if [ -f CIEvidence/phase2-visual-acceptance-manifest.json ]; then
  exec python3 Scripts/phase2_results.py --manifest CIEvidence/phase2-visual-acceptance-manifest.json gate --categories animation-stage,animation-sequence
fi

DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"
APP_ID="de.nicofroeba16.iosnext"
OUT_DIR="${OUT_DIR:-AnimationAcceptance}"
APPEARANCE="${APPEARANCE:-light}"
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
mkdir -p "$OUT_DIR/stages" "$OUT_DIR/logs"

stop_recording() {
  if [ -n "$record_pid" ]; then
    kill -INT "$record_pid" 2>/dev/null || true
    wait "$record_pid" 2>/dev/null || true
    record_pid=""
  fi
}
trap stop_recording EXIT

set_visual_baseline() {
  xcrun simctl ui "$device_id" appearance "$APPEARANCE"
  xcrun simctl ui "$device_id" content_size large
  xcrun simctl ui "$device_id" increase_contrast disabled
  xcrun simctl spawn "$device_id" defaults write com.apple.Accessibility ReduceMotionEnabled -bool false
  xcrun simctl spawn "$device_id" defaults write com.apple.Accessibility ReduceTransparencyEnabled -bool false
  xcrun simctl spawn "$device_id" notifyutil -p com.apple.Accessibility.ReduceMotionStatusDidChange || true
  xcrun simctl spawn "$device_id" notifyutil -p com.apple.Accessibility.ReduceTransparencyStatusDidChange || true

  local state=""
  for _ in {1..40}; do
    state="$(xcrun simctl ui "$device_id" appearance 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
    if [[ "$state" == *"$APPEARANCE"* ]]; then
      return 0
    fi
    sleep 0.1
  done
  echo "Appearance failed to settle: expected=$APPEARANCE actual=$state" >&2
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

capture_stage() {
  local stage="$1"
  local destination
  local attempt nonce marker candidate launch_log validation_log
  destination="$OUT_DIR/stages/stage-$(printf '%02d' "$stage").png"

  rm -f "$destination"

  for attempt in 1 2 3 4; do
    nonce="animation-$stage-$attempt-$(uuidgen | tr '[:upper:]' '[:lower:]')"
    marker="$data_container/tmp/iosnext-animation-stage-ready-$stage-$nonce"
    candidate="$OUT_DIR/logs/stage-$stage-attempt-$attempt.png"
    launch_log="$OUT_DIR/logs/stage-$stage-attempt-$attempt-launch.log"
    validation_log="$OUT_DIR/logs/stage-$stage-attempt-$attempt-validation.log"

    rm -f "$marker" "$candidate" "$launch_log" "$validation_log"
    xcrun simctl terminate "$device_id" "$APP_ID" 2>/dev/null || true

    if xcrun simctl launch "$device_id" "$APP_ID"       --animation-acceptance-mode       "--animation-stage=$stage"       "--visual-ready-nonce=$nonce"       >"$launch_log" 2>&1; then
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

  echo "Unable to capture animation stage $stage" >&2
  return 1
}

for stage in 0 1 2 3 4 5 6 7; do
  capture_stage "$stage"
done

stage_count="$(find "$OUT_DIR/stages" -name 'stage-*.png' | wc -l | tr -d ' ')"
test "$stage_count" -eq 8
unique_stage_hashes="$(shasum -a 256 "$OUT_DIR"/stages/stage-*.png | awk '{print $1}' | sort -u | wc -l | tr -d ' ')"
test "$unique_stage_hashes" -eq 8

record_animation_video() {
  local video="$OUT_DIR/animation-acceptance.mp4"
  local attempt bytes validation_log

  for attempt in 1 2 3; do
    validation_log="$OUT_DIR/logs/video-attempt-$attempt-validation.log"
    rm -f "$video" "$validation_log"
    xcrun simctl terminate "$device_id" "$APP_ID" 2>/dev/null || true

    xcrun simctl io "$device_id" recordVideo --codec=h264 "$video"       >"$OUT_DIR/logs/video-attempt-$attempt-record.log" 2>&1 &
    record_pid=$!
    sleep 0.35

    if ! xcrun simctl launch "$device_id" "$APP_ID"       --animation-acceptance-mode       "--visual-ready-nonce=animation-video-$attempt-$(uuidgen | tr '[:upper:]' '[:lower:]')"       >"$OUT_DIR/logs/video-attempt-$attempt-launch.log" 2>&1; then
      stop_recording
      continue
    fi

    sleep 16
    stop_recording

    if [ -s "$video" ]; then
      bytes="$(stat -f%z "$video")"
      if [ "$bytes" -gt 200000 ]         && xcrun swift Scripts/validate_visual_video.swift "$video" animation >"$validation_log" 2>&1; then
        echo "$bytes"
        return 0
      fi
    fi

    if [ "$attempt" -eq 2 ]; then
      restart_simulator
    fi
  done

  echo "Unable to record valid animation video" >&2
  return 1
}

video_bytes="$(record_animation_video)"

cat > "$OUT_DIR/summary.txt" <<EOF
Animation Acceptance
device=$DEVICE_NAME
appearance=$APPEARANCE
stage_screenshots=$stage_count
unique_stage_hashes=$unique_stage_hashes
video_bytes=$video_bytes
video_frame_validation=true
sequence=app-start,navigation,light-toggle,conditional,media-play-pause,slider,chat,owner-area
capture_strategy=nonce-ready-marker-plus-frame-settle-plus-validation
video_retry=true
simulator_restart_after_repeated_capture_failure=true
EOF
