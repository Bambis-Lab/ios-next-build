"""Validate distributed native results, not G03 as a whole.

This offline verifier accepts no credentials and makes no network calls.
The originating test jobs must preserve raw XCResult bundles independently.
"""
import json
import math
import re
import sys
from pathlib import Path

HEX=re.compile(r"[0-9a-f]{64}")
SHA=re.compile(r"[0-9a-f]{40}")
UUID=re.compile(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}")
FIELDS={"version","source","run","attempt","duration","role","build_sha256","host_boot_sha256",
        "simulator","xcresult_device","test_name","test_pass","pid","sent","received","elapsed_seconds",
        "media_started_utc","media_finished_utc","relay_session_sha256","renewals","physical_audio"}

def require(ok,reason):
    if not ok: raise ValueError(reason)

def validate(a,b,*,source,run,attempt,duration):
    require(type(duration) is int and duration in (30,120,300),"invalid_duration")
    require(isinstance(source,str) and SHA.fullmatch(source),"invalid_source")
    require(isinstance(run,str) and re.fullmatch(r"[0-9]{1,24}",run),"invalid_run")
    require(isinstance(attempt,str) and re.fullmatch(r"[0-9]{1,10}",attempt),"invalid_attempt")
    for role,item in (("A",a),("B",b)):
        require(isinstance(item,dict) and set(item)==FIELDS,"invalid_schema")
        require(type(item["version"]) is int and item["version"]==1 and item["role"]==role,"invalid_role")
        require(item["source"]==source and item["run"]==run and item["attempt"]==attempt and
                type(item["duration"]) is int and item["duration"]==duration,"source_or_stage_mismatch")
        for field in ("build_sha256","host_boot_sha256","relay_session_sha256"):
            require(isinstance(item[field],str) and HEX.fullmatch(item[field]),"invalid_digest")
        require(isinstance(item["simulator"],str) and UUID.fullmatch(item["simulator"]) and
                item["xcresult_device"]==item["simulator"],"invalid_destination")
        require(item["test_name"]=="testDistributed"+role and item["test_pass"] is True and
                item["physical_audio"] is False,"not_native_distributed_test")
        require(type(item["pid"]) is int and item["pid"]>0,"invalid_pid")
        require(all(type(item[k]) is int for k in ("sent","received","renewals")) and
                item["sent"]==item["received"]==duration*50 and item["renewals"]==2,"incomplete_media")
        for field in ("elapsed_seconds","media_started_utc","media_finished_utc"):
            require(type(item[field]) in (int,float) and math.isfinite(item[field]) and item[field]>=0,"invalid_timing")
        require(duration<=item["elapsed_seconds"]<=duration+15,"invalid_elapsed")
        wall=item["media_finished_utc"]-item["media_started_utc"]
        require(abs(wall-item["elapsed_seconds"])<=2,"wall_monotonic_mismatch")
    require(a["build_sha256"]==b["build_sha256"],"different_products")
    require(a["host_boot_sha256"]!=b["host_boot_sha256"],"same_host")
    require(a["relay_session_sha256"]==b["relay_session_sha256"],"different_relay_session")
    overlap=min(a["media_finished_utc"],b["media_finished_utc"])-max(a["media_started_utc"],b["media_started_utc"])
    require(overlap>=duration-2,"insufficient_simultaneous_media")
    return {"status":"PASS_NATIVE_DISTRIBUTED_MEDIA_STAGE","duration_seconds":duration,
            "source":source,"run":run,"attempt":attempt,"overlap_seconds":round(overlap,3),
            "total_frames":duration*100,"physical_audio":False,"g03":"REMAINING_GATES_REQUIRED"}

def read(path):
    file=Path(path)
    require(file.is_file() and not file.is_symlink() and file.stat().st_size<=16384,"invalid_evidence_file")
    return json.loads(file.read_text(encoding="utf-8"))

if __name__=="__main__":
    if len(sys.argv)!=7:
        raise SystemExit("usage: validate_distributed_media.py A.json B.json SOURCE RUN ATTEMPT DURATION")
    try:
        print(json.dumps(validate(read(sys.argv[1]),read(sys.argv[2]),source=sys.argv[3],
            run=sys.argv[4],attempt=sys.argv[5],duration=int(sys.argv[6])),sort_keys=True))
    except (ValueError,OSError,TypeError,KeyError):
        raise SystemExit("V64_DISTRIBUTED_MEDIA_VALIDATION_FAILED")
