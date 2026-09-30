#!/usr/bin/env bash
set -euo pipefail

DEVICE_NAME="${DEVICE_NAME:-iPhone 18 Pro Max}"
APP_ID="de.nicofroeba16.iosnext"
OUT_DIR="${OUT_DIR:-MotionSmokeAcceptance}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PWD/.motion-smoke-derived}"
GOLDENS="${MOTION_GOLDENS_DIR:-MotionGoldens/iPhone-18-Pro-Max-iOS27-dark}"
FRAMES="$OUT_DIR/frames"
LOGS="$OUT_DIR/logs"
SIMULATOR_UDID=""
MOTION_DEVICE_NAME="IOSNext-Motion-Smoke-${DEVICE_NAME// /-}-$$"

# Deliberately sparse high-signal frames: boundaries + characteristic midpoints.
STARTUP_FRAMES=(0 8 16 24 31 42 86)
UNLOCK_FRAMES=(0 8 20 38 50 83 108)
LOCK_FRAMES=(0 5 14 20 26)
TOTAL_FRAMES=19
CAPTURED=0

run_with_timeout() {
  local limit="$1" label="$2"; shift 2
  "$@" & local pid=$! start=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do
    if [ $((SECONDS-start)) -ge "$limit" ]; then
      echo "MOTION_SMOKE_TIMEOUT label=$label limit=${limit}s" >&2
      kill -TERM "$pid" 2>/dev/null || true; sleep 1
      kill -KILL "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
  done
  wait "$pid"
}

command -v xcodegen >/dev/null 2>&1 || { echo 'xcodegen required' >&2; exit 1; }
command -v xcrun >/dev/null 2>&1 || { echo 'xcrun required' >&2; exit 1; }
rm -rf "$OUT_DIR" "$DERIVED_DATA_PATH"
mkdir -p "$FRAMES" "$LOGS" "$DERIVED_DATA_PATH"

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

runtime_id="$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(r["identifier"] for r in d["runtimes"] if r.get("isAvailable",True) and r.get("name")=="iOS 27.0"))')"
dtype="$(DEVICE_NAME="$DEVICE_NAME" xcrun simctl list devicetypes -j | DEVICE_NAME="$DEVICE_NAME" python3 -c 'import json,os,sys; d=json.load(sys.stdin); n=os.environ["DEVICE_NAME"]; print(next(x["identifier"] for x in d["devicetypes"] if x.get("name")==n))')"
SIMULATOR_UDID="$(xcrun simctl create "$MOTION_DEVICE_NAME" "$dtype" "$runtime_id")"
xcrun simctl boot "$SIMULATOR_UDID" 2>/dev/null || true
run_with_timeout 120 boot xcrun simctl bootstatus "$SIMULATOR_UDID" -b
xcrun simctl ui "$SIMULATOR_UDID" appearance dark
xcrun simctl ui "$SIMULATOR_UDID" content_size large
xcrun simctl spawn "$SIMULATOR_UDID" defaults write com.apple.Accessibility ReduceMotionEnabled -bool false
xcrun simctl status_bar "$SIMULATOR_UDID" override --time 09:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true

run_with_timeout 900 build-for-testing xcodebuild build-for-testing \
  -project IOSNext.xcodeproj \
  -scheme IOSNext \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  CODE_SIGNING_ALLOWED=NO

APP_PATH="$(find "$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator" -maxdepth 1 -type d -name 'IOSNext.app' -print -quit)"
test -d "$APP_PATH"
xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"
DATA_CONTAINER="$(xcrun simctl get_app_container "$SIMULATOR_UDID" "$APP_ID" data)"

capture_one() {
  local sequence="$1" frame="$2" attempt nonce marker out payload expected
  mkdir -p "$FRAMES/$sequence"
  out="$FRAMES/$sequence/frame-$(printf '%03d' "$frame").png"
  for attempt in 1 2; do
    nonce="smoke-${sequence}-${frame}-${attempt}-$(uuidgen | tr '[:upper:]' '[:lower:]')"
    marker="$DATA_CONTAINER/tmp/iosnext-motion-ready-${sequence}-${frame}-${nonce}"
    rm -f "$marker" "$out"
    xcrun simctl terminate "$SIMULATOR_UDID" "$APP_ID" 2>/dev/null || true
    run_with_timeout 15 launch xcrun simctl launch "$SIMULATOR_UDID" "$APP_ID" \
      "--motion-acceptance-sequence=$sequence" "--motion-frame=$frame" "--visual-ready-nonce=$nonce" \
      >"$LOGS/${sequence}-$(printf '%03d' "$frame")-$attempt.log" 2>&1
    for _ in {1..100}; do [ -f "$marker" ] && break; sleep .1; done
    if [ -f "$marker" ]; then
      payload="$(cat "$marker")"; expected="sequence=$sequence;frame=$(printf '%03d' "$frame");"
      if [[ "$payload" == "$expected"* ]]; then
        sleep .12
        xcrun simctl io "$SIMULATOR_UDID" screenshot "$out" >/dev/null
        [ -s "$out" ] && { CAPTURED=$((CAPTURED+1)); echo "MOTION_SMOKE_PROGRESS $CAPTURED/$TOTAL_FRAMES $sequence:$frame"; return 0; }
      fi
    fi
  done
  echo "motion smoke capture failed: $sequence frame=$frame" >&2
  return 1
}

for f in "${STARTUP_FRAMES[@]}"; do capture_one startup "$f"; done
for f in "${UNLOCK_FRAMES[@]}"; do capture_one control-center-unlock "$f"; done
for f in "${LOCK_FRAMES[@]}"; do capture_one control-center-lock "$f"; done
test "$CAPTURED" -eq "$TOTAL_FRAMES"

python3 - "$FRAMES" "$GOLDENS" "$OUT_DIR/smoke-manifest.json" <<'PY'
import hashlib, json, sys
from pathlib import Path
from PIL import Image, ImageChops
frames, goldens, output = map(Path, sys.argv[1:])
selected = {
  'startup':[0,8,16,24,31,42,86],
  'control-center-unlock':[0,8,20,38,50,83,108],
  'control-center-lock':[0,5,14,20,26],
}
result={'schema_version':1,'profile':'smoke','frames':[],'ok':True}
for seq, indices in selected.items():
  for i in indices:
    p=frames/seq/f'frame-{i:03d}.png'; g=goldens/seq/p.name
    if not p.is_file(): raise SystemExit(f'missing {p}')
    entry={'sequence':seq,'frame':i,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
    if g.is_file():
      with Image.open(p).convert('RGBA') as a, Image.open(g).convert('RGBA') as b:
        if a.size != b.size:
          entry['golden_ok']=False
        else:
          d=ImageChops.difference(a,b); h=d.histogram(); total=sum(h)
          mean=sum((n%256)*c for n,c in enumerate(h))/max(total,1)
          high=sum(c for n,c in enumerate(h) if (n%256)>12)/max(total,1)
          entry['mean_abs_delta']=round(mean,6); entry['ratio_delta_gt_12']=round(high,8)
          entry['golden_ok']=mean<=1.5 and high<=0.005
        result['ok'] = result['ok'] and entry['golden_ok']
    result['frames'].append(entry)
output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
if (goldens/'.enforced').exists() and not result['ok']: raise SystemExit(1)
PY

printf 'MOTION_SMOKE_ACCEPTANCE=PASS\ntotal_frames=%s\n' "$TOTAL_FRAMES" | tee "$OUT_DIR/summary.txt"
