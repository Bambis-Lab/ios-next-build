#!/usr/bin/env python3
"""Compare REAL iOS Next Instruments-exported scenario metrics. No synthetic claims.

JSON format:
{"schema":"iosnext.perf.v1","environment":{"device":"iPhone ...","os":"iOS 27", 
"mode":"Release","fixture":"fixture-v1"},
 "scenarios":{"Nico.Open":{"p50_ms":120,"p95_ms":230,"peak_rss_mb":190}}}

Exit nonzero on missing evidence, mismatched environments, or a >5% p95
regression. Improvements are reported only for real supplied measurements.
"""
import argparse
import json
import math
import pathlib
import sys

REQUIRED = ("p50_ms", "p95_ms")
ENV = ("device", "os", "mode", "fixture")

def load(path):
    doc = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    if doc.get("schema") != "iosnext.perf.v1":
        raise ValueError(f"{path}: incorrect measurement schema")
    if not isinstance(doc.get("environment"), dict):
        raise ValueError(f"{path}: missing environment")
    if not isinstance(doc.get("scenarios"), dict) or not doc["scenarios"]:
        raise ValueError(f"{path}: missing scenarios")
    for scenario, metrics in doc["scenarios"].items():
        for key in REQUIRED:
            value = metrics.get(key)
            if not isinstance(value, (int, float)) or isinstance(value, bool) or not math.isfinite(value) or value <= 0:
                raise ValueError(f"{path}: {scenario}/{key} invalid")
        if metrics["p50_ms"] > metrics["p95_ms"]:
            raise ValueError(f"{path}: {scenario} p50 exceeds p95")
    return doc

def compare(baseline, optimized, max_regression):
    for key in ENV:
        if baseline["environment"].get(key) != optimized["environment"].get(key):
            raise ValueError(f"not comparable: environment {key} differs")
    if set(baseline["scenarios"]) != set(optimized["scenarios"]):
        raise ValueError("not comparable: scenarios differ")
    report = {}
    for scenario in sorted(baseline["scenarios"]):
        before=baseline["scenarios"][scenario]
        after=optimized["scenarios"][scenario]
        ratios={}
        for metric in REQUIRED:
            ratios[metric] = round((after[metric] / before[metric] - 1) * 100, 2)
        report[scenario] = {
            "baseline": {key: before[key] for key in REQUIRED},
            "candidate": {key: after[key] for key in REQUIRED},
            "delta_percent": ratios,
            "p95_gate": "PASS" if ratios["p95_ms"] <= max_regression * 100 else "FAIL",
        }
    return report

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline")
    parser.add_argument("candidate")
    parser.add_argument("--max-p95-regression", type=float, default=0.05)
    args = parser.parse_args()
    try:
        a,b=load(args.baseline),load(args.candidate)
        report=compare(a,b,args.max_p95_regression)
        print(json.dumps(report, indent=2, ensure_ascii=False, sort_keys=True))
        return 0 if all(x["p95_gate"] == "PASS" for x in report.values()) else 1
    except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print(f"PERF_COMPARISON_INVALID: {exc}", file=sys.stderr)
        return 2

if __name__ == "__main__":
    raise SystemExit(main())
