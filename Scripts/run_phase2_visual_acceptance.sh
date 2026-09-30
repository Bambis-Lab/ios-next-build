#!/bin/bash
set -euo pipefail

APP_ID="de.nicofroeba16.iosnext"
MATRIX="UITests/VisualAcceptanceMatrix.json"
MATRIX_HEAD="dafb1ae63da7bccad28d6cc40aa95a06ec342426"
MATRIX_JSON_SHA256="0fad724ea19da47266a46405db951cfa7a715f0c237fb0cf50852e98665a097c"
MATRIX_DOC_SHA256="acad10e9c85fb9eb65fc7c5fbf9681f65daf6dd84aa6db598c7af17d1eccb17e"
MANIFEST="CIEvidence/phase2-visual-acceptance-manifest.json"
TEST_METHOD="IOSNextUITests/IOSNextUITests/testPhase2Scenario"

: "${DERIVED_DATA_PATH:?DERIVED_DATA_PATH must point to current-run DerivedData}"
: "${XCTESTRUN_PATH:?XCTESTRUN_PATH must point to current-run xctestrun}"
test -d "$DERIVED_DATA_PATH"
test -f "$XCTESTRUN_PATH"
case "$XCTESTRUN_PATH" in
  "$DERIVED_DATA_PATH"/*) ;;
  *) echo "XCTESTRUN_PATH escaped current DerivedData" >&2; exit 2 ;;
esac

matrix_json_hash="$(shasum -a 256 "$MATRIX" | awk '{print $1}')"
matrix_doc_hash="$(shasum -a 256 UITests/VISUAL_ACCEPTANCE_MATRIX.md | awk '{print $1}')"
test "$matrix_json_hash" = "$MATRIX_JSON_SHA256" || { echo "Phase-1 matrix JSON hash drift: $matrix_json_hash" >&2; exit 3; }
test "$matrix_doc_hash" = "$MATRIX_DOC_SHA256" || { echo "Phase-1 matrix documentation hash drift: $matrix_doc_hash" >&2; exit 3; }
python3 Scripts/validate_visual_acceptance_matrix.py

rm -rf UIAcceptance CardScreenshots AnimationAcceptance DarkVisualAcceptance
mkdir -p UIAcceptance/phase2 CardScreenshots/phase2 AnimationAcceptance/phase2 DarkVisualAcceptance/phase2 CIEvidence
execution_head="$(git rev-parse HEAD)"
python3 Scripts/phase2_results.py --manifest "$MANIFEST" init --matrix-head "$MATRIX_HEAD" --execution-head "$execution_head"

devices_json="$(xcrun simctl list devices available -j)"
iphone_id="$(printf '%s' "$devices_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for r,ds in d["devices"].items() if r.endswith("iOS-27-0") for x in ds if x.get("isAvailable", True) and x["name"]=="iPhone 18 Pro Max"))')"
ipad_id="$(printf '%s' "$devices_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for r,ds in d["devices"].items() if r.endswith("iOS-27-0") for x in ds if x.get("isAvailable", True) and x["name"].startswith("iPad")))')"
test -n "$iphone_id"
test -n "$ipad_id"
printf 'iphone=%s\nipad=%s\n' "$iphone_id" "$ipad_id" | tee CIEvidence/phase2-devices.txt

for device_id in "$iphone_id" "$ipad_id"; do
  xcrun simctl boot "$device_id" 2>/dev/null || true
  xcrun simctl bootstatus "$device_id" -b
  xcrun simctl terminate "$device_id" "$APP_ID" 2>/dev/null || true
done

set_reduce_motion() {
  xcrun simctl spawn "$1" defaults write com.apple.Accessibility ReduceMotionEnabled -bool "$2"
  xcrun simctl spawn "$1" notifyutil -p com.apple.Accessibility.ReduceMotionStatusDidChange || true
}

set_reduce_transparency() {
  xcrun simctl spawn "$1" defaults write com.apple.Accessibility ReduceTransparencyEnabled -bool "$2"
  xcrun simctl spawn "$1" notifyutil -p com.apple.Accessibility.ReduceTransparencyStatusDidChange || true
}

reset_accessibility() {
  local device_id="$1"
  xcrun simctl ui "$device_id" content_size large
  xcrun simctl ui "$device_id" increase_contrast disabled
  set_reduce_motion "$device_id" false
  set_reduce_transparency "$device_id" false
}

configure_variant() {
  local scenario="$1" device_id="$2" appearance="$3"
  reset_accessibility "$device_id"
  xcrun simctl ui "$device_id" appearance "$appearance"
  case "$scenario" in
    A11Y-001) xcrun simctl ui "$device_id" content_size accessibility-extra-extra-extra-large ;;
    A11Y-002) set_reduce_motion "$device_id" true ;;
    A11Y-003) set_reduce_transparency "$device_id" true ;;
    A11Y-004) xcrun simctl ui "$device_id" increase_contrast enabled ;;
  esac
  xcrun simctl terminate "$device_id" "$APP_ID" 2>/dev/null || true
}

reboot_for_final_attempt() {
  local device_id="$1"
  xcrun simctl terminate "$device_id" "$APP_ID" 2>/dev/null || true
  xcrun simctl shutdown "$device_id" 2>/dev/null || true
  xcrun simctl boot "$device_id"
  xcrun simctl bootstatus "$device_id" -b
}

scenario_value() {
  local scenario="$1" field="$2"
  python3 - "$scenario" "$field" <<'PY'
import json,sys
scenario_id, field = sys.argv[1:3]
manifest=json.load(open("UITests/VisualAcceptanceMatrix.json"))
item=next(x for x in manifest["scenarios"] if x["id"]==scenario_id)
value=item
for key in field.split("."):
    value=value[key]
if isinstance(value, list):
    print(",".join(str(x) for x in value))
else:
    print(value)
PY
}

retryable_class() {
  local scenario="$1" failure_class="$2"
  python3 - "$scenario" "$failure_class" <<'PY'
import json,sys
sid, failure = sys.argv[1:3]
manifest=json.load(open("UITests/VisualAcceptanceMatrix.json"))
item=next(x for x in manifest["scenarios"] if x["id"]==sid)
raise SystemExit(0 if failure in item["retry_policy"]["retryable"] else 1)
PY
}

make_xctestrun() {
  local destination="$1" scenario="$2" appearance="$3" orientation="$4"
  cp "$XCTESTRUN_PATH" "$destination"
  python3 - "$destination" "$scenario" "$appearance" "$orientation" <<'PY'
import plistlib,sys
path, scenario, appearance, orientation = sys.argv[1:5]
with open(path,"rb") as f:
    data=plistlib.load(f)
env={
    "IOSNEXT_PHASE2_SCENARIO_ID": scenario,
    "IOSNEXT_PHASE2_APPEARANCE": appearance,
    "IOSNEXT_PHASE2_ORIENTATION": orientation,
}
patched=0
def walk(obj):
    global patched
    if isinstance(obj, dict):
        marker=" ".join(str(obj.get(k,"")) for k in ("TestBundlePath","BlueprintName","TestHostPath"))
        if "IOSNextUITests" in marker:
            current=dict(obj.get("EnvironmentVariables",{}))
            current.update(env)
            obj["EnvironmentVariables"]=current
            patched += 1
        for value in obj.values():
            walk(value)
    elif isinstance(obj, list):
        for value in obj:
            walk(value)
walk(data)
if patched < 1:
    raise SystemExit("Unable to locate IOSNextUITests target in xctestrun")
with open(path,"wb") as f:
    plistlib.dump(data,f,fmt=plistlib.FMT_XML)
PY
}

classify_failure() {
  local log="$1"
  local tagged
  tagged="$(grep -Eo 'PHASE2_CLASS=[a-z_]+' "$log" 2>/dev/null | tail -1 | cut -d= -f2 || true)"
  if [ -n "$tagged" ]; then echo "$tagged"; return; fi
  if grep -qE 'Visual-ready probe|Visual frame did not settle|probe missing|probe not ready' "$log"; then echo ready_timeout; return; fi
  if grep -qE 'blank/flat|Screenshot remained' "$log"; then echo blank_or_flat_capture; return; fi
  if grep -q 'Orientation did not settle' "$log"; then echo orientation_mismatch; return; fi
  if grep -qE 'did not become hittable|outside the visible application window' "$log"; then echo interaction_unhittable; return; fi
  echo wrong_surface
}

evidence_root() {
  local category="$1"
  case "$category" in
    card-catalog) echo "CardScreenshots/phase2" ;;
    animation-stage|animation-sequence) echo "AnimationAcceptance/phase2" ;;
    cold-launch) echo "DarkVisualAcceptance/phase2" ;;
    *) echo "UIAcceptance/phase2" ;;
  esac
}

device_tuple() {
  case "$1" in
    iphone-18-pro-max) printf '%s\t%s\n' "$iphone_id" portrait ;;
    ipad-portrait) printf '%s\t%s\n' "$ipad_id" portrait ;;
    ipad-landscape) printf '%s\t%s\n' "$ipad_id" landscape ;;
    *) return 1 ;;
  esac
}

run_variant() {
  local scenario="$1" logical_device="$2" appearance="$3"
  local tuple device_id orientation category root variant max_attempts attempt
  tuple="$(device_tuple "$logical_device")" || return 1
  device_id="${tuple%%$'\t'*}"
  orientation="${tuple#*$'\t'}"
  category="$(scenario_value "$scenario" category)"
  max_attempts="$(scenario_value "$scenario" retry_policy.max_attempts)"
  variant="${logical_device}__${appearance}"
  root="$(evidence_root "$category")/$scenario/$variant"
  mkdir -p "$root" UIAcceptance/phase2-xctestruns

  for attempt in $(seq 1 "$max_attempts"); do
    local attempt_log result_bundle xctestrun_copy failure_class rc evidence video video_pid validation_log
    attempt_log="$root/attempt-$attempt.log"
    result_bundle="$root/attempt-$attempt.xcresult"
    xctestrun_copy="UIAcceptance/phase2-xctestruns/${scenario}-${variant}-attempt-${attempt}.xctestrun"
    video=""
    video_pid=""
    validation_log=""
    rm -rf "$result_bundle" "$xctestrun_copy"

    if [ "$attempt" -eq "$max_attempts" ] && [ "$attempt" -gt 1 ]; then
      reboot_for_final_attempt "$device_id" >>"$attempt_log" 2>&1 || true
    fi
    if ! configure_variant "$scenario" "$device_id" "$appearance" >>"$attempt_log" 2>&1; then
      python3 Scripts/phase2_results.py --manifest "$MANIFEST" record --scenario "$scenario" --variant "$variant" --status BLOCKED --attempts "$attempt" --failure-class external_state_leak --log "$attempt_log"
      return 0
    fi

    if ! make_xctestrun "$xctestrun_copy" "$scenario" "$appearance" "$orientation" >>"$attempt_log" 2>&1; then
      python3 Scripts/phase2_results.py --manifest "$MANIFEST" record --scenario "$scenario" --variant "$variant" --status BLOCKED --attempts "$attempt" --failure-class selector_contract --log "$attempt_log"
      return 0
    fi

    if [ "$scenario" = "CLD-001" ] || [ "$scenario" = "ANIM-009" ]; then
      video="$root/attempt-$attempt.mp4"
      validation_log="$root/attempt-$attempt-video-validation.log"
      rm -f "$video" "$validation_log"
      xcrun simctl io "$device_id" recordVideo --codec=h264 "$video" >"$root/attempt-$attempt-video-record.log" 2>&1 &
      video_pid=$!
      sleep 0.35
    fi

    set +e
    xcodebuild test-without-building \
      -xctestrun "$xctestrun_copy" \
      -destination "platform=iOS Simulator,id=$device_id" \
      "-only-testing:$TEST_METHOD" \
      -resultBundlePath "$result_bundle" \
      2>&1 | tee -a xcodebuild.log | tee -a "$attempt_log"
    rc=${PIPESTATUS[0]}
    set -e

    if [ -n "$video_pid" ]; then
      kill -INT "$video_pid" 2>/dev/null || true
      wait "$video_pid" 2>/dev/null || true
      video_pid=""
    fi

    failure_class=""
    if [ "$rc" -eq 0 ] && [ -n "$video" ]; then
      mode=animation
      [ "$scenario" = "CLD-001" ] && mode=cold
      if ! xcrun swift Scripts/validate_visual_video.swift "$video" "$mode" >"$validation_log" 2>&1; then
        rc=1
        failure_class=video_transition_gap
      fi
    fi

    evidence="$result_bundle"
    [ -n "$video" ] && evidence="$evidence,$video"
    if [ "$rc" -eq 0 ]; then
      python3 Scripts/phase2_results.py --manifest "$MANIFEST" record \
        --scenario "$scenario" --variant "$variant" --status PASS --attempts "$attempt" \
        --evidence "$evidence" --log "$attempt_log"
      return 0
    fi

    [ -n "$failure_class" ] || failure_class="$(classify_failure "$attempt_log")"
    if [ "$attempt" -lt "$max_attempts" ] && retryable_class "$scenario" "$failure_class"; then
      echo "Retrying $scenario $variant after $failure_class ($attempt/$max_attempts)" | tee -a "$attempt_log"
      continue
    fi

    python3 Scripts/phase2_results.py --manifest "$MANIFEST" record \
      --scenario "$scenario" --variant "$variant" --status FAIL --attempts "$attempt" \
      --failure-class "$failure_class" --evidence "$evidence" --log "$attempt_log"
    return 0
  done
}

# cleanup is invoked indirectly by the EXIT trap.
# shellcheck disable=SC2329,SC2317
cleanup() {
  set +e
  for device_id in "$iphone_id" "$ipad_id"; do
    xcrun simctl terminate "$device_id" "$APP_ID" 2>/dev/null || true
    reset_accessibility "$device_id" >/dev/null 2>&1 || true
    xcrun simctl ui "$device_id" appearance light >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

python3 - <<'PY' > CIEvidence/phase2-plan.tsv
import json
m=json.load(open("UITests/VisualAcceptanceMatrix.json"))
for scenario in m["scenarios"]:
    appearances=scenario.get("variants",{}).get("appearance",["light"])
    devices=scenario.get("variants",{}).get("devices",["iphone-18-pro-max"])
    for device in devices:
        for appearance in appearances:
            print(scenario["id"], device, appearance, sep="\t")
PY

planned_variants="$(wc -l < CIEvidence/phase2-plan.tsv | tr -d ' ')"
echo "Phase2 planned variants: $planned_variants" | tee CIEvidence/phase2-execution.txt

while IFS=$'\t' read -r scenario logical_device appearance; do
  echo "=== PHASE2 $scenario $logical_device $appearance ===" | tee -a CIEvidence/phase2-execution.txt
  run_variant "$scenario" "$logical_device" "$appearance"
done < CIEvidence/phase2-plan.tsv

python3 Scripts/phase2_results.py --manifest "$MANIFEST" finalize | tee -a CIEvidence/phase2-execution.txt
python3 - "$MANIFEST" <<'PY' | tee CIEvidence/phase2-summary.txt
import json,sys
m=json.load(open(sys.argv[1]))
print("matrix_head="+m["matrix_head"])
print("execution_head="+m["execution_head"])
print("counts="+json.dumps(m["counts"],sort_keys=True))
for sid,scenario in m["scenarios"].items():
    print(f"{sid}={scenario['status']}")
PY

# Return success so the workflow reaches the category gates and always uploads the complete manifest.
exit 0
