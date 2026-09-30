#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MATRIX_PATH = ROOT / "UITests" / "VisualAcceptanceMatrix.json"
DEFAULT_MANIFEST = ROOT / "CIEvidence" / "phase2-visual-acceptance-manifest.json"

def now():
    return datetime.now(timezone.utc).isoformat()

def load_matrix():
    return json.loads(MATRIX_PATH.read_text())

def load_manifest(path):
    return json.loads(Path(path).read_text())

def save_manifest(path, data):
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")

def expected_variants(scenario):
    variants = scenario.get("variants", {})
    appearances = variants.get("appearance", ["light"])
    devices = variants.get("devices", ["iphone-18-pro-max"])
    return [f"{device}__{appearance}" for device in devices for appearance in appearances]

def init_manifest(args):
    matrix = load_matrix()
    scenarios = {}
    for item in matrix["scenarios"]:
        scenarios[item["id"]] = {
            "category": item["category"],
            "surface": item["surface"],
            "expected_variants": expected_variants(item),
            "variants": {},
            "status": "BLOCKED",
            "reason": "not executed",
        }
    data = {
        "goal_version": "native-ios-visual-final-acceptance-phase2-v1",
        "matrix_head": args.matrix_head,
        "execution_head": args.execution_head,
        "started_at": now(),
        "completed_at": None,
        "scenarios": scenarios,
        "counts": {"PASS": 0, "FAIL": 0, "BLOCKED": len(scenarios)},
        "artifacts": [],
    }
    save_manifest(args.manifest, data)

def record_variant(args):
    data = load_manifest(args.manifest)
    scenario = data["scenarios"][args.scenario]
    scenario["variants"][args.variant] = {
        "status": args.status,
        "attempts": args.attempts,
        "failure_class": args.failure_class or None,
        "evidence": args.evidence or None,
        "log": args.log or None,
        "updated_at": now(),
    }
    scenario["reason"] = None
    save_manifest(args.manifest, data)

def recompute(data):
    counts = {"PASS": 0, "FAIL": 0, "BLOCKED": 0}
    for scenario in data["scenarios"].values():
        expected = scenario["expected_variants"]
        actual = scenario["variants"]
        missing = [key for key in expected if key not in actual]
        statuses = [actual[key]["status"] for key in expected if key in actual]
        if "FAIL" in statuses:
            scenario["status"] = "FAIL"
            scenario["reason"] = "one or more required variants failed"
        elif "BLOCKED" in statuses or missing:
            scenario["status"] = "BLOCKED"
            scenario["reason"] = "missing or blocked required variants: " + ",".join(missing)
        else:
            scenario["status"] = "PASS"
            scenario["reason"] = None
        counts[scenario["status"]] += 1
    data["counts"] = counts
    return data

def collect_artifacts():
    roots = [ROOT / name for name in (
        "UIAcceptance", "CardScreenshots", "AnimationAcceptance",
        "DarkVisualAcceptance", "CIEvidence",
    )]
    artifacts = []
    for base in roots:
        if not base.exists():
            continue
        for current, dirs, files in os.walk(base):
            current_path = Path(current)
            xcresults = [d for d in dirs if d.endswith(".xcresult")]
            for name in sorted(xcresults):
                bundle = current_path / name
                artifacts.append({"path": bundle.relative_to(ROOT).as_posix(), "kind": "xcresult"})
            dirs[:] = [d for d in dirs if not d.endswith(".xcresult")]
            for name in sorted(files):
                path = current_path / name
                rel = path.relative_to(ROOT).as_posix()
                if rel.endswith("phase2-visual-acceptance-manifest.json"):
                    continue
                digest = hashlib.sha256(path.read_bytes()).hexdigest()
                artifacts.append({
                    "path": rel,
                    "kind": "file",
                    "bytes": path.stat().st_size,
                    "sha256": digest,
                })
    return artifacts

def finalize(args):
    data = recompute(load_manifest(args.manifest))
    data["completed_at"] = now()
    data["artifacts"] = collect_artifacts()
    save_manifest(args.manifest, data)
    print(json.dumps({"counts": data["counts"], "artifacts": len(data["artifacts"])}, sort_keys=True))

def gate(args):
    data = recompute(load_manifest(args.manifest))
    categories = set(args.categories.split(",")) if args.categories else None
    chosen = [s for s in data["scenarios"].values() if categories is None or s["category"] in categories]
    bad = [s for s in chosen if s["status"] != "PASS"]
    if bad:
        for scenario_id, scenario in data["scenarios"].items():
            if scenario in bad:
                print(f"{scenario_id}: {scenario['status']} {scenario.get('reason') or ''}")
        raise SystemExit(1)
    print(f"Phase2 gate PASS: {len(chosen)} scenarios")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    sub = parser.add_subparsers(dest="command", required=True)

    p_init = sub.add_parser("init")
    p_init.add_argument("--matrix-head", required=True)
    p_init.add_argument("--execution-head", required=True)
    p_init.set_defaults(func=init_manifest)

    p_record = sub.add_parser("record")
    p_record.add_argument("--scenario", required=True)
    p_record.add_argument("--variant", required=True)
    p_record.add_argument("--status", choices=["PASS", "FAIL", "BLOCKED"], required=True)
    p_record.add_argument("--attempts", type=int, required=True)
    p_record.add_argument("--failure-class", default="")
    p_record.add_argument("--evidence", default="")
    p_record.add_argument("--log", default="")
    p_record.set_defaults(func=record_variant)

    p_finalize = sub.add_parser("finalize")
    p_finalize.set_defaults(func=finalize)

    p_gate = sub.add_parser("gate")
    p_gate.add_argument("--categories", default="")
    p_gate.set_defaults(func=gate)

    args = parser.parse_args()
    args.func(args)

if __name__ == "__main__":
    main()
