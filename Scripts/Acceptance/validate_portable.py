#!/usr/bin/env python3
import json
import pathlib
import subprocess

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROFILE = ROOT / "Scripts/Acceptance/block_profiles.json"


def main() -> None:
    data = json.loads(PROFILE.read_text(encoding="utf-8"))
    assert data["schema_version"] == 1
    assert set(data["blocks"]) == set("ABCDE")
    assert data["blocks"]["A"]["ready"] is True
    for block in "BCDE":
        assert data["blocks"][block]["ready"] is False, f"{block} must fail closed until its tests exist"

    scripts = [
        ROOT / "Scripts/Acceptance/run_block_gate.sh",
        ROOT / "Scripts/Acceptance/run_motion_smoke_acceptance.sh",
    ]
    for script in scripts:
        subprocess.run(["bash", "-n", str(script)], check=True)

    scope_source = (ROOT / "Scripts/Acceptance/check_block_scope.py").read_text(encoding="utf-8")
    compile(scope_source, "check_block_scope.py", "exec")

    smoke = (ROOT / "Scripts/Acceptance/run_motion_smoke_acceptance.sh").read_text(encoding="utf-8")
    assert "TOTAL_FRAMES=19" in smoke
    assert "STARTUP_FRAMES=(0 8 16 24 31 42 86)" in smoke
    assert "UNLOCK_FRAMES=(0 8 20 38 50 83 108)" in smoke
    assert "LOCK_FRAMES=(0 5 14 20 26)" in smoke

    gate = (ROOT / "Scripts/Acceptance/run_block_gate.sh").read_text(encoding="utf-8")
    assert "MOTION_GOLDENS_ENFORCED=PASS total_frames=223" in gate
    assert "MOTION_GOLDENS_BOOTSTRAP=READY" in gate
    assert "MotionGoldens-iPhone-18-Pro-Max-iOS27-dark.zip" in gate
    assert "full motion gate had no enforced baseline; generated downloadable candidate goldens instead" in gate
    assert 'if [ ! -d "$MOTION_GOLDENS_DIR" ] || [ ! -f "$MOTION_GOLDENS_DIR/.enforced" ]; then' in gate

    codemagic = yaml.safe_load((ROOT / "codemagic.yaml").read_text(encoding="utf-8"))
    workflow = codemagic["workflows"]["iosnext-block-gate"]
    assert workflow["max_build_duration"] == 35
    assert workflow["inputs"]["block"]["options"] == ["A", "B", "C", "D", "E"]
    assert workflow["inputs"]["mode"]["options"] == ["fast", "full"]
    assert "iosnext-free-sideload" in codemagic["workflows"]

    print("BLOCK_ACCEPTANCE_PORTABLE=PASS")


if __name__ == "__main__":
    main()
