#!/usr/bin/env python3
"""Read-only source audit: reproducible inventory and conservative risk signals.
No secrets, backend calls, signing or deployments. Python 3 stdlib only.
"""
import argparse
import hashlib
import json
import re
import subprocess
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RULES = [
    ("AUD-GESTURE-001", "P0", "Direct remote-state slider binding", re.compile(r"Slider\s*\(\s*value:\s*Binding\s*\("), ["Sources/Design/IOS27DashboardCards.swift"]),
    ("AUD-TASK-001", "P1", "Unstructured task creation", re.compile(r"\bTask\s*\{"), []),
    ("AUD-TASK-002", "P2", "Cancellation-swallowing task sleep", re.compile(r"try\?\s+await\s+Task\.sleep"), []),
    ("AUD-MAIN-001", "P1", "Potential main-thread synchronous IO", re.compile(r"\bData\s*\(\s*contentsOf:|\bString\s*\(\s*contentsOf:"), []),
    ("AUD-SAFETY-001", "P1", "Force operation requires review", re.compile(r"\btry!\b|\bas!\b|\bfatalError\s*\("), []),
    ("AUD-RENDER-001", "P2", "View-scoped sorting or filtering requires profiling", re.compile(r"\.sorted\s*\{|\.filter\s*\{"), []),
    ("AUD-NET-001", "P2", "Direct shared URLSession use requires ownership review", re.compile(r"URLSession\.shared"), []),
]
def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()

def inventory():
    entries = []
    for p in sorted(ROOT.rglob("*.swift")):
        if ".git" in p.parts or "build" in p.parts or ".build" in p.parts:
            continue
        rel = p.relative_to(ROOT).as_posix()
        data = p.read_bytes()
        entries.append({"path":rel,"sha256":hashlib.sha256(data).hexdigest(),
                        "git_blob":git("hash-object", "--", rel),
                        "bytes":len(data),"lines":data.count(b"\n")+int(not data.endswith(b"\n"))})
    return entries

def scan(entries):
    findings=[]
    for entry in entries:
        path=entry["path"]
        lines=(ROOT/path).read_text(encoding="utf-8").splitlines()
        for lineno,line in enumerate(lines,1):
            for rid,severity,desc,pattern,_ in RULES:
                if pattern.search(line):
                    findings.append({"id":rid,"priority":severity,"path":path,"line":lineno,
                                     "description":desc,"status":"requires_review",
                                     "evidence":line.strip()[:220]})
    return findings

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--out",default="build/source-audit")
    args=parser.parse_args()
    out=ROOT/args.out
    out.mkdir(parents=True,exist_ok=True)
    entries=inventory()
    findings=scan(entries)
    sha=git("rev-parse","HEAD")
    grouped=Counter(x["id"] for x in findings)
    summary={"commit":sha,"file_count":len(entries),
             "source_count":sum(x["path"].startswith("Sources/") for x in entries),
             "test_count":sum(x["path"].startswith(("Tests/","UITests/")) for x in entries),
             "total_bytes":sum(x["bytes"] for x in entries),
             "signal_counts":dict(sorted(grouped.items())),
             "warning":"Static signals are NOT confirmed runtime bugs; human review and tests required."}
    (out/"source-lock.json").write_text(json.dumps({"summary":summary,"files":entries},indent=2)+"\n")
    (out/"risk-signals.json").write_text(json.dumps({"summary":summary,"findings":findings},indent=2)+"\n")
    lines=["# iOS Next source audit — immutable CI evidence","",
           f"Commit: \`{sha}\`",f"Swift files: {len(entries)}",
           f"Production: {summary['source_count']}; Tests/UITests: {summary['test_count']}",
           f"Bytes: {summary['total_bytes']}","",
           "## Heuristic signals (not proven defects)","",
           "| Rule | Occurrences |","|---|---:|"]
    lines.extend(f"| {key} | {count} |" for key,count in sorted(grouped.items()))
    lines += ["","## All signals with source location","","| Severity | Rule | File:line |","|---|---|---|"]
    lines.extend(f"| {x['priority']} | {x['id']} | \`{x['path']}:{x['line']}\` |" for x in findings)
    (out/"audit-report.md").write_text("\n".join(lines)+"\n")
    assert len(entries)>=150, "Unexpected source inventory shrinkage"
    assert summary["source_count"]>=125
    print(json.dumps(summary,indent=2))
if __name__=="__main__":
    main()
