#!/usr/bin/env bash
set -euo pipefail

DEVICE_NAME="${DEVICE_NAME:-iPhone 18 Pro Max}"
APP_ID="de.nicofroeba16.iosnext"
OUT_DIR="${OUT_DIR:-MotionAcceptance}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PWD/.motion-derived}"
FRAMES="$OUT_DIR/frames"
LOGS="$OUT_DIR/logs"
GOLDENS="${MOTION_GOLDENS_DIR:-MotionGoldens/iPhone-18-Pro-Max-iOS27-dark}"
MOTION_DEVICE_NAME="IOSNext-Motion-${DEVICE_NAME// /-}-$$"
SIMULATOR_UDID=""
CAPTURED_COUNT=0
TOTAL_FRAMES=223
CI_PYTHON="$PWD/.ci-venv/bin/python"
if [ ! -x "$CI_PYTHON" ]; then
  CI_PYTHON="$(command -v python3)"
fi

run_with_timeout() {
  local timeout_seconds="$1"
  local label="$2"
  shift 2
  local started=$SECONDS
  local heartbeat_bucket=0
  local child rc elapsed bucket

  "$@" &
  child=$!
  while kill -0 "$child" 2>/dev/null; do
    elapsed=$((SECONDS - started))
    if [ "$elapsed" -ge "$timeout_seconds" ]; then
      echo "MOTION_TIMEOUT label=$label elapsed=${elapsed}s limit=${timeout_seconds}s" >&2
      kill -TERM "$child" 2>/dev/null || true
      sleep 2
      kill -KILL "$child" 2>/dev/null || true
      wait "$child" 2>/dev/null || true
      return 124
    fi
    bucket=$((elapsed / 15))
    if [ "$bucket" -gt "$heartbeat_bucket" ]; then
      heartbeat_bucket="$bucket"
      echo "MOTION_HEARTBEAT label=$label elapsed=${elapsed}s"
    fi
    sleep 1
  done

  set +e
  wait "$child"
  rc=$?
  set -e
  return "$rc"
}

"$CI_PYTHON" Scripts/validate_motion_spec.py
"$CI_PYTHON" -c 'from PIL import Image, ImageChops; print("Motion image engine: Pillow")'
command -v xcodegen >/dev/null 2>&1 || { echo 'xcodegen is required' >&2; exit 1; }
command -v xcrun >/dev/null 2>&1 || { echo 'xcrun is required' >&2; exit 1; }

# The motion job is self-contained. A fresh project is generated from the canonical
# source so stale Xcode project state can never affect frame acceptance.
bash Scripts/prepare_wireguard_dependency.sh
xcodegen generate

cleanup() {
  if [ -n "$SIMULATOR_UDID" ]; then
    xcrun simctl terminate "$SIMULATOR_UDID" "$APP_ID" 2>/dev/null || true
    xcrun simctl shutdown "$SIMULATOR_UDID" 2>/dev/null || true
    xcrun simctl delete "$SIMULATOR_UDID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

runtime_id="$(xcrun simctl list runtimes -j | "$CI_PYTHON" -c 'import json,sys; d=json.load(sys.stdin); print(next(r["identifier"] for r in d["runtimes"] if r.get("isAvailable",True) and r.get("name")=="iOS 27.0"))')"
dtype="$(DEVICE_NAME="$DEVICE_NAME" xcrun simctl list devicetypes -j | DEVICE_NAME="$DEVICE_NAME" "$CI_PYTHON" -c 'import json,os,sys; d=json.load(sys.stdin); n=os.environ["DEVICE_NAME"]; print(next(x["identifier"] for x in d["devicetypes"] if x.get("name")==n))')"
SIMULATOR_UDID="$(xcrun simctl create "$MOTION_DEVICE_NAME" "$dtype" "$runtime_id")"
test -n "$SIMULATOR_UDID"

set_visual_baseline() {
  xcrun simctl ui "$SIMULATOR_UDID" appearance dark
  xcrun simctl ui "$SIMULATOR_UDID" content_size large
  xcrun simctl ui "$SIMULATOR_UDID" increase_contrast disabled || true
  xcrun simctl spawn "$SIMULATOR_UDID" defaults write com.apple.Accessibility ReduceMotionEnabled -bool false
  xcrun simctl spawn "$SIMULATOR_UDID" defaults write com.apple.Accessibility ReduceTransparencyEnabled -bool false
  xcrun simctl spawn "$SIMULATOR_UDID" notifyutil -p com.apple.Accessibility.ReduceMotionStatusDidChange || true
  xcrun simctl spawn "$SIMULATOR_UDID" notifyutil -p com.apple.Accessibility.ReduceTransparencyStatusDidChange || true
  xcrun simctl status_bar "$SIMULATOR_UDID" override \
    --time 09:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true
}

boot_simulator() {
  xcrun simctl boot "$SIMULATOR_UDID" 2>/dev/null || true
  run_with_timeout 120 "simulator-bootstatus" xcrun simctl bootstatus "$SIMULATOR_UDID" -b
  set_visual_baseline
}

restart_simulator() {
  run_with_timeout 10 "simulator-terminate" xcrun simctl terminate "$SIMULATOR_UDID" "$APP_ID" 2>/dev/null || true
  run_with_timeout 20 "simulator-shutdown" xcrun simctl shutdown "$SIMULATOR_UDID" 2>/dev/null || true
  boot_simulator
}

boot_simulator

rm -rf "$DERIVED_DATA_PATH" "$OUT_DIR"
mkdir -p "$DERIVED_DATA_PATH" "$FRAMES" "$LOGS"

# build-for-testing intentionally remains here: the following final acceptance step
# reuses the same DerivedData with test-without-building.
run_with_timeout 900 "xcode-build-for-testing" xcodebuild build-for-testing \
  -project IOSNext.xcodeproj \
  -scheme IOSNext \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$LOGS/build-for-testing.log"

APP_PATH="$(find "$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator" -maxdepth 1 -type d -name 'IOSNext.app' -print -quit)"
test -n "$APP_PATH"
test -d "$APP_PATH"

run_with_timeout 20 "simulator-uninstall" xcrun simctl uninstall "$SIMULATOR_UDID" "$APP_ID" 2>/dev/null || true
run_with_timeout 30 "simulator-install" xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"
DATA_CONTAINER="$(xcrun simctl get_app_container "$SIMULATOR_UDID" "$APP_ID" data)"
test -d "$DATA_CONTAINER"

capture_frame() {
  local sequence="$1"
  local frame="$2"
  local destination
  local attempt nonce marker candidate launch_log payload expected_prefix ready
  destination="$FRAMES/$sequence/frame-$(printf '%03d' "$frame").png"

  mkdir -p "$FRAMES/$sequence"
  rm -f "$destination"

  for attempt in 1 2 3; do
    nonce="motion-${sequence}-${frame}-${attempt}-$(uuidgen | tr '[:upper:]' '[:lower:]')"
    marker="$DATA_CONTAINER/tmp/iosnext-motion-ready-${sequence}-${frame}-${nonce}"
    candidate="$LOGS/${sequence}-$(printf '%03d' "$frame")-attempt-${attempt}.png"
    launch_log="$LOGS/${sequence}-$(printf '%03d' "$frame")-attempt-${attempt}-launch.log"

    rm -f "$marker" "$candidate" "$launch_log"
    run_with_timeout 10 "terminate-${sequence}-${frame}-${attempt}" \
      xcrun simctl terminate "$SIMULATOR_UDID" "$APP_ID" 2>/dev/null || true

    if run_with_timeout 15 "launch-${sequence}-${frame}-${attempt}" \
      xcrun simctl launch "$SIMULATOR_UDID" "$APP_ID" \
      "--motion-acceptance-sequence=$sequence" \
      "--motion-frame=$frame" \
      "--visual-ready-nonce=$nonce" \
      >"$launch_log" 2>&1; then
      ready=0
      for _ in {1..120}; do
        if [ -f "$marker" ]; then
          ready=1
          break
        fi
        sleep 0.1
      done

      if [ "$ready" -eq 1 ]; then
        payload="$(cat "$marker")"
        expected_prefix="sequence=$sequence;frame=$(printf '%03d' "$frame");"
        if [[ "$payload" == "$expected_prefix"* ]]; then
          # Give SpringBoard one additional render tick after the in-app ready marker.
          sleep 0.12
          if run_with_timeout 15 "screenshot-${sequence}-${frame}-${attempt}" \
            xcrun simctl io "$SIMULATOR_UDID" screenshot "$candidate" >/dev/null; then
            if [ -s "$candidate" ]; then
              mv "$candidate" "$destination"
              CAPTURED_COUNT=$((CAPTURED_COUNT + 1))
              echo "MOTION_CAPTURE_PROGRESS captured=$CAPTURED_COUNT/$TOTAL_FRAMES sequence=$sequence frame=$(printf '%03d' "$frame") attempt=$attempt"
              return 0
            fi
          fi
        else
          printf 'ready marker payload mismatch: expected_prefix=%s actual=%s\n' \
            "$expected_prefix" "$payload" >>"$launch_log"
        fi
      else
        echo "ready marker timeout: $marker" >>"$launch_log"
      fi
    fi

    echo "MOTION_CAPTURE_RETRY sequence=$sequence frame=$(printf '%03d' "$frame") attempt=$attempt" >&2
    if [ "$attempt" -eq 2 ]; then
      restart_simulator
      DATA_CONTAINER="$(xcrun simctl get_app_container "$SIMULATOR_UDID" "$APP_ID" data)"
      test -d "$DATA_CONTAINER"
    fi
  done

  echo "Unable to capture motion frame: sequence=$sequence frame=$frame" >&2
  return 1
}

capture_sequence() {
  local sequence="$1"
  local count="$2"
  local frame
  echo "MOTION_SEQUENCE_START sequence=$sequence frames=$count"
  for ((frame=0; frame<count; frame++)); do
    capture_frame "$sequence" "$frame"
  done
  echo "MOTION_SEQUENCE_DONE sequence=$sequence captured=$CAPTURED_COUNT/$TOTAL_FRAMES"
}

capture_sequence startup 87
capture_sequence control-center-unlock 109
capture_sequence control-center-lock 27

echo "MOTION_CAPTURE_COMPLETE captured=$CAPTURED_COUNT/$TOTAL_FRAMES"
test "$CAPTURED_COUNT" -eq "$TOTAL_FRAMES"

run_with_timeout 300 "motion-artifact-validation" "$CI_PYTHON" Scripts/validate_motion_artifacts.py \
  --frames "$FRAMES" \
  --goldens "$GOLDENS" \
  --output "$OUT_DIR/motion-frame-manifest.json"

if command -v ffmpeg >/dev/null 2>&1; then
  run_with_timeout 120 "ffmpeg-startup" ffmpeg -hide_banner -loglevel error -y -framerate 120 \
    -i "$FRAMES/startup/frame-%03d.png" -c:v libx264 -pix_fmt yuv420p -r 120 "$OUT_DIR/startup-120fps.mp4"
  run_with_timeout 120 "ffmpeg-unlock" ffmpeg -hide_banner -loglevel error -y -framerate 120 \
    -i "$FRAMES/control-center-unlock/frame-%03d.png" -c:v libx264 -pix_fmt yuv420p -r 120 "$OUT_DIR/control-center-unlock-120fps.mp4"
  run_with_timeout 120 "ffmpeg-lock" ffmpeg -hide_banner -loglevel error -y -framerate 120 \
    -i "$FRAMES/control-center-lock/frame-%03d.png" -c:v libx264 -pix_fmt yuv420p -r 120 "$OUT_DIR/control-center-lock-120fps.mp4"
fi

printf 'MOTION_ACCEPTANCE=PASS\ndevice=%s\nos=iOS 27.0\nmaster_fps=120\nstartup_frames=87\nunlock_frames=109\nlock_frames=27\ntotal_frames=223\ngoldens=%s\ncapture_strategy=host-simctl-fresh-simulator-ready-marker-timeboxed\n' \
  "$DEVICE_NAME" "$GOLDENS" | tee "$OUT_DIR/summary.txt"
