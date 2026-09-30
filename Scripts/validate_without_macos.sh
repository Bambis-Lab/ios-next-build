#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

python3 - <<'PY'
import importlib.util
missing = [name for name in ("yaml", "cryptography", "websockets") if importlib.util.find_spec(name) is None]
if missing:
    raise SystemExit(
        "Missing CI validation dependencies: " + ", ".join(missing)
        + ". Install Scripts/requirements-ci.txt before running the release preflight."
    )
PY

git diff --check
bash Scripts/validate_canonical_source.sh
python3 Scripts/validate_app_icon.py

if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout Info.plist
  xmllint --noout Sources/Resources/PrivacyInfo.xcprivacy
else
  python3 -c 'import plistlib; plistlib.load(open("Info.plist", "rb"))'
  python3 -c 'import plistlib; plistlib.load(open("Sources/Resources/PrivacyInfo.xcprivacy", "rb"))'
fi

while IFS= read -r -d '' asset_json; do
  python3 -m json.tool "$asset_json" >/dev/null
done < <(find Assets.xcassets -name Contents.json -print0)

if command -v rg >/dev/null 2>&1; then
  rg -q 'IPHONEOS_DEPLOYMENT_TARGET: 27\.0' project.yml
else
  grep -Eq 'IPHONEOS_DEPLOYMENT_TARGET: 27\.0' project.yml
fi

credential_pattern='(Bearer[[:space:]]+[A-Za-z0-9._-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|eyJ[A-Za-z0-9_-]{20,}\.)'
if command -v rg >/dev/null 2>&1; then
  credential_matches="$(rg -n --hidden -g '!**/.git/**' -g '!**/__pycache__/**' -g '!**/.ci-venv/**' -g '!**/*.pyc' -g '!Scripts/validate_without_macos.sh' \
    "$credential_pattern" . || true)"
else
  credential_matches="$(grep -ERn --exclude-dir=.git --exclude-dir=__pycache__ --exclude-dir=.ci-venv --exclude='*.pyc' --exclude=validate_without_macos.sh \
    "$credential_pattern" . || true)"
fi
if [[ -n "$credential_matches" ]]; then
  printf '%s\n' "$credential_matches"
  echo 'Potential credential material found.' >&2
  exit 1
fi

bash -n \
  Scripts/run_phase2_visual_acceptance.sh \
  Scripts/run_ui_acceptance_matrix.sh \
  Scripts/capture_live_card_screenshots.sh \
  Scripts/run_dark_visual_acceptance.sh \
  Scripts/run_animation_acceptance.sh \
  Scripts/run_motion_frame_acceptance.sh
python3 -m py_compile \
  Scripts/phase2_results.py \
  Scripts/validate_visual_acceptance_matrix.py \
  Scripts/validate_phase2_execution_support.py \
  Scripts/fake_ha_websocket_server.py \
  Scripts/validate_motion_spec.py \
  Scripts/validate_motion_artifacts.py \
  Scripts/validate_motion_capture_contract.py \
  Scripts/validate_110_contracts.py \
  Scripts/validate_layout_lock.py
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck Scripts/run_phase2_visual_acceptance.sh Scripts/run_ui_acceptance_matrix.sh \
    Scripts/capture_live_card_screenshots.sh Scripts/run_dark_visual_acceptance.sh Scripts/run_animation_acceptance.sh \
    Scripts/run_motion_frame_acceptance.sh
fi
grep -q 'func testPhase2Scenario()' UITests/IOSNextUITests.swift

python3 Scripts/validate_visual_acceptance_matrix.py
python3 Scripts/validate_phase2_execution_support.py
python3 Scripts/validate_motion_spec.py
python3 Scripts/validate_motion_capture_contract.py
python3 Scripts/validate_pre_xcode_source.py
python3 Scripts/validate_product_contracts.py
python3 Scripts/validate_110_contracts.py
python3 Scripts/validate_layout_lock.py
python3 Scripts/validate_release_metadata.py
python3 - <<'PY'
import yaml
from pathlib import Path

workflow_root = Path(".github/workflows")
expected_files = ["ios-next-getmac-final-acceptance.yml", "validate.yml"]
files = sorted(path.name for path in workflow_root.glob("*.yml"))
if files != expected_files:
    raise SystemExit(f"iOS workflow set must be exactly {expected_files}, got: {files}")

validate_payload = yaml.safe_load((workflow_root / "validate.yml").read_text(encoding="utf-8"))
if not isinstance(validate_payload, dict) or "jobs" not in validate_payload:
    raise SystemExit("Invalid Greenfield iOS validation workflow YAML")
if validate_payload.get("permissions") != {"contents": "read"}:
    raise SystemExit("Greenfield iOS validation workflow must be contents: read")

getmac_path = workflow_root / "ios-next-getmac-final-acceptance.yml"
getmac_payload = yaml.load(getmac_path.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
if not isinstance(getmac_payload, dict) or "jobs" not in getmac_payload:
    raise SystemExit("Invalid GetMac final acceptance workflow YAML")
triggers = getmac_payload.get("on")
if not isinstance(triggers, dict) or set(triggers) != {"workflow_dispatch"}:
    raise SystemExit(f"GetMac final acceptance must be manual-only workflow_dispatch, got: {triggers}")
if getmac_payload.get("permissions") != {"contents": "read"}:
    raise SystemExit("GetMac final acceptance workflow must be contents: read")
PY
python3 - <<'PY'
from pathlib import Path
import yaml

payload = yaml.safe_load(Path("codemagic.yaml").read_text(encoding="utf-8"))
workflows = payload.get("workflows") if isinstance(payload, dict) else None
if not isinstance(workflows, dict):
    raise SystemExit("Invalid Codemagic workflows mapping")
workflow = workflows.get("iosnext-free-sideload")
if not isinstance(workflow, dict):
    raise SystemExit("Missing Codemagic release workflow")
scripts = workflow.get("scripts")
if not isinstance(scripts, list) or not scripts:
    raise SystemExit("Codemagic release workflow has no script steps")
for index, step in enumerate(scripts, start=1):
    if not isinstance(step, dict) or not isinstance(step.get("name"), str) or not isinstance(step.get("script"), str):
        raise SystemExit(f"Invalid Codemagic script step {index}")
print(f"Codemagic workflow structure valid: {len(scripts)} script steps")
PY

python3 Scripts/sync_owner_addon.py --check
bash -n HAAddons/iosnext-owner-admin/run.sh
python3 -m py_compile Backend/admin_service/*.py Backend/commander_live/*.py Backend/tests/*.py HAAddons/iosnext-owner-admin/admin_service/*.py Scripts/sync_owner_addon.py PrivilegeBroker/iosnext_privilege_broker.py
python3 - <<'PY'
import yaml
from pathlib import Path
for name in ("config.yaml", "build.yaml"):
    payload = yaml.safe_load((Path("HAAddons/iosnext-owner-admin") / name).read_text())
    if not isinstance(payload, dict):
        raise SystemExit(f"Invalid add-on YAML: {name}")
assert payload is not None
PY
PYTHONPATH=Backend python3 -m unittest discover -s Backend/tests >/dev/null

echo 'Non-macOS validation passed.'
