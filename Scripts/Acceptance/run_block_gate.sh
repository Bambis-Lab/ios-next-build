#!/usr/bin/env bash
set -euo pipefail

BLOCK="${1:-}"
MODE="${2:-fast}"
PROFILE_FILE="${BLOCK_PROFILE_FILE:-Scripts/Acceptance/block_profiles.json}"
DEVICE_NAME="${DEVICE_NAME:-iPhone 18 Pro Max}"
IOS_VERSION="${IOS_VERSION:-27.0}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() { echo "BLOCK_GATE_FAIL: $*" >&2; exit 1; }

case "$BLOCK" in A|B|C|D|E) ;; *) fail "block must be A, B, C, D or E" ;; esac
case "$MODE" in fast|full) ;; *) fail "mode must be fast or full" ;; esac

command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild is required; run this gate on macOS"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
command -v xcodegen >/dev/null 2>&1 || fail "xcodegen is required"

eval "$(python3 - "$PROFILE_FILE" "$BLOCK" "$MODE" <<'PY'
import json, shlex, sys
path, block, mode = sys.argv[1:]
data = json.load(open(path, encoding='utf-8'))
p = data['blocks'][block]
print('PROFILE_READY=' + ('1' if p.get('ready') else '0'))
print('PROFILE_TITLE=' + shlex.quote(p['title']))
print('REQUIRES_FAKE_HA=' + ('1' if p.get('requires_fake_ha') else '0'))
print('RUN_MOTION=' + ('1' if p.get('motion_' + mode) else '0'))
selectors = p.get(mode + '_unit_selectors', [])
print('TEST_SELECTORS=' + shlex.quote('\n'.join(selectors)))
PY
)"

[ "$PROFILE_READY" = "1" ] || fail "block $BLOCK profile is intentionally not enabled yet"

echo "BLOCK_GATE block=$BLOCK mode=$MODE title=$PROFILE_TITLE"

OUT_ROOT="${BLOCK_GATE_OUT_ROOT:-${CM_BUILD_DIR:-$ROOT}/BlockAcceptance}"
OUT_DIR="$OUT_ROOT/$BLOCK/$MODE"
DERIVED="${BLOCK_GATE_DERIVED_DATA:-${CM_BUILD_DIR:-$ROOT}/.block-derived-$BLOCK}"
RESULT="$OUT_DIR/BlockGate.xcresult"
mkdir -p "$OUT_DIR"
rm -rf "$RESULT"

source Scripts/ci_runtime.sh
export CI_RUNTIME_SCOPE="block-$BLOCK-$MODE"
runtime_start "total"

validate_golden_tree() {
  local root="$1"
  python3 - "$root" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
expected = {'startup': 87, 'control-center-unlock': 109, 'control-center-lock': 27}
for sequence, count in expected.items():
    directory = root / sequence
    files = sorted(directory.glob('frame-*.png')) if directory.is_dir() else []
    if len(files) != count:
        raise SystemExit(f'BLOCK_GATE_FAIL: enforced goldens incomplete for {sequence}: {len(files)} != {count}')
    missing = [i for i in range(count) if not (directory / f'frame-{i:03d}.png').is_file()]
    if missing:
        raise SystemExit(f'BLOCK_GATE_FAIL: enforced goldens missing frames for {sequence}: {missing[:8]}')
print('MOTION_GOLDENS_ENFORCED=PASS total_frames=223')
PY
}

bootstrap_motion_goldens() {
  local motion_out="$1"
  local candidate_parent="$OUT_DIR/MotionGoldens"
  local candidate_root="$candidate_parent/iPhone-18-Pro-Max-iOS27-dark"
  local candidate_zip="$OUT_DIR/MotionGoldens-iPhone-18-Pro-Max-iOS27-dark.zip"

  echo "MOTION_GOLDENS_BOOTSTRAP start=1 reason=missing_enforced_baseline"
  rm -rf "$candidate_parent" "$candidate_zip"

  DEVICE_NAME="$DEVICE_NAME" \
  DERIVED_DATA_PATH="$DERIVED" \
  OUT_DIR="$motion_out" \
  MOTION_GOLDENS_DIR="$OUT_DIR/.candidate-goldens-not-present" \
    bash Scripts/run_motion_frame_acceptance.sh

  mkdir -p "$candidate_root"
  cp -R "$motion_out/frames/." "$candidate_root/"
  touch "$candidate_root/.enforced"
  validate_golden_tree "$candidate_root"

  (
    cd "$OUT_DIR"
    zip -qry "$(basename "$candidate_zip")" "MotionGoldens"
  )
  test -s "$candidate_zip"
  echo "MOTION_GOLDENS_BOOTSTRAP=READY"
  echo "MOTION_GOLDENS_ARTIFACT=$candidate_zip"
  echo "Download and review the MotionGoldens ZIP from this Codemagic build, then add the extracted MotionGoldens directory to the source used by the full gate." >&2
  fail "full motion gate had no enforced baseline; generated downloadable candidate goldens instead"
}

if [ "$RUN_MOTION" = "1" ]; then
  runtime_start "motion"
  MOTION_OUT_DIR="$OUT_DIR/MotionAcceptance"
  MOTION_GOLDENS_DIR="${MOTION_GOLDENS_DIR:-${CM_BUILD_DIR:-$ROOT}/MotionGoldens/iPhone-18-Pro-Max-iOS27-dark}"
  if [ "$MODE" = "fast" ]; then
    DEVICE_NAME="$DEVICE_NAME" \
    DERIVED_DATA_PATH="$DERIVED" \
    OUT_DIR="$MOTION_OUT_DIR" \
    MOTION_GOLDENS_DIR="$MOTION_GOLDENS_DIR" \
      bash Scripts/Acceptance/run_motion_smoke_acceptance.sh
  else
    if [ ! -d "$MOTION_GOLDENS_DIR" ] || [ ! -f "$MOTION_GOLDENS_DIR/.enforced" ]; then
      bootstrap_motion_goldens "$MOTION_OUT_DIR"
    fi
    validate_golden_tree "$MOTION_GOLDENS_DIR"
    DEVICE_NAME="$DEVICE_NAME" \
    DERIVED_DATA_PATH="$DERIVED" \
    OUT_DIR="$MOTION_OUT_DIR" \
    MOTION_GOLDENS_DIR="$MOTION_GOLDENS_DIR" \
      bash Scripts/run_motion_frame_acceptance.sh
  fi
  runtime_end "motion"
else
  runtime_start "prepare"
  bash Scripts/prepare_wireguard_dependency.sh
  xcodegen generate
  runtime_end "prepare"

  runtime_start "build-for-testing"
  xcodebuild build-for-testing \
    -project IOSNext.xcodeproj \
    -scheme IOSNext \
    -derivedDataPath "$DERIVED" \
    -destination "platform=iOS Simulator,name=$DEVICE_NAME,OS=$IOS_VERSION" \
    CODE_SIGNING_ALLOWED=NO
  runtime_end "build-for-testing"
fi

FAKE_HA_PID=""
cleanup() {
  if [ -n "$FAKE_HA_PID" ]; then
    kill "$FAKE_HA_PID" 2>/dev/null || true
    wait "$FAKE_HA_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [ "$REQUIRES_FAKE_HA" = "1" ]; then
  FAKE_HA_PORT="${FAKE_HA_PORT:-18765}"
  python3 Scripts/fake_ha_websocket_server.py --port "$FAKE_HA_PORT" >"$OUT_DIR/fake-ha.log" 2>&1 &
  FAKE_HA_PID=$!
  python3 - "$FAKE_HA_PORT" <<'PY'
import socket, sys, time
port = int(sys.argv[1]); deadline = time.time() + 10
while time.time() < deadline:
    with socket.socket() as sock:
        if sock.connect_ex(('127.0.0.1', port)) == 0:
            raise SystemExit(0)
    time.sleep(.1)
raise SystemExit('fake HA did not become ready')
PY
fi

if [ -n "$TEST_SELECTORS" ]; then
  args=()
  while IFS= read -r selector; do
    [ -n "$selector" ] && args+=("-only-testing:$selector")
  done <<< "$TEST_SELECTORS"

  runtime_start "selected-tests"
  xcodebuild test-without-building \
    -project IOSNext.xcodeproj \
    -scheme IOSNext \
    -derivedDataPath "$DERIVED" \
    -destination "platform=iOS Simulator,name=$DEVICE_NAME,OS=$IOS_VERSION" \
    -resultBundlePath "$RESULT" \
    "${args[@]}" \
    CODE_SIGNING_ALLOWED=NO
  runtime_end "selected-tests"
fi

runtime_end "total"
runtime_render_json "$OUT_DIR/runtime.json"
printf 'BLOCK_ACCEPTANCE=PASS\nblock=%s\nmode=%s\n' "$BLOCK" "$MODE" | tee "$OUT_DIR/summary.txt"
