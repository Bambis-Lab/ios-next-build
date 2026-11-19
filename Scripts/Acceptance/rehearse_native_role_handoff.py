"""Rehearse role-file handoff on hosted iOS simulator; no relay or sockets."""
import json
import os
from pathlib import Path
import re
import sys
from boot_simulator import run_bounded

def require(ok,reason):
    if not ok: raise RuntimeError(reason)

def rehearse():
    from distributed_role_provisioning import generate
    from native_role_handoff import install_role
    require(os.environ.get("GITHUB_ACTIONS")=="true" and
            os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted","disposable_host_required")
    role=os.environ["IOSNEXT_PREFLIGHT_ROLE"]
    uid=os.environ["SIM_ID"]
    require(role in ("A","B"),"wrong_role")
    out=Path("build/ios173/dual-simulator")
    pre=json.loads((out/"preflight.json").read_text())
    require(pre["role"]==role and pre["simulator"]==uid and pre["native_test_pass"] is True
            and pre["source"]==os.environ["GITHUB_SHA"] and pre["run"]==os.environ["GITHUB_RUN_ID"]
            and pre["attempt"]==os.environ["GITHUB_RUN_ATTEMPT"],"missing_current_native_preflight")
    # The successful prerequisite already installed this disposable test app.
    # Locate only its sandbox; do not touch any existing real user profile.
    container=Path(run_bounded(["xcrun","simctl","get_app_container",uid,
         "de.nicofroeba16.iosnext","data"],timeout=30,emit_output=False).strip())
    _,roles=generate(os.environ["GITHUB_RUN_ID"]+":"+os.environ["GITHUB_RUN_ATTEMPT"],
        30,"https://fixture.invalid/")
    raw=json.dumps(roles[role],separators=(",",":")).encode("ascii")
    target=install_role(raw,container,role,30)
    result=out/("role-"+role+".xcresult")
    try:
        log=run_bounded(["xcodebuild","test-without-building","-collect-test-diagnostics","never",
            "-xctestrun",str(Path(os.environ["XCTESTRUN_PATH"]).resolve()),"-destination","platform=iOS Simulator,id="+uid,
            "-parallel-testing-enabled","NO","-disable-concurrent-destination-testing",
            "-resultBundlePath",str(result.resolve()),
            "-only-testing:IOSNextTests/FamilyAudioIndependentSimulatorTests/testOfflineRoleHandoff"+role,
            "CODE_SIGNING_ALLOWED=YES","CODE_SIGNING_REQUIRED=YES","CODE_SIGN_IDENTITY=-"],
            timeout=480,emit_output=False)
        require(log.count("V65_OFFLINE_NATIVE_ROLE_HANDOFF=PASS role="+role)==1
            and re.search(r"Executed 1 test[s]?, with 0 failures",log)
            and re.search(r"\*\* TEST (?:EXECUTE )?SUCCEEDED \*\*",log),"native_role_read_failed")
        summary=run_bounded(["xcrun","xcresulttool","get","test-results","summary","--path",str(result)],
            timeout=60,emit_output=False)
        require(uid.lower() in summary.lower(),"wrong_result_destination")
        require(target.is_file() and target.read_bytes()==raw,"role_file_changed")
        # Never publish a source role file or any bearer/key material.
        require(all(x not in log and x not in summary for x in roles[role]["tokens"]+[roles[role]["signingSeed"]]),
                "sensitive_output_detected")
        (out/"handoff-summary.json").write_text(summary)
    finally:
        target.unlink(missing_ok=True)
    require(not target.exists(),"cleanup_failed")
    (out/"handoff-evidence.json").write_text(json.dumps({"role":role,"source":pre["source"],
        "run":pre["run"],"attempt":pre["attempt"],"simulator":uid,
        "build_sha256":pre["build_sha256"],"host_boot_sha256":pre["boot_session_sha256"],
        "native_role_read":True,"wrong_role_rejected":True,"wrong_duration_rejected":True,
        "transient_file_removed":True,"network_used":False,"media_tested":False},indent=2)+"\n")
    print("V65_OFFLINE_ROLE_HANDOFF_COMPLETE role="+role)

def validate():
    root=Path("build/preflight")
    data=[]
    for role in ("A","B"):
        matches=list((root/("V64-preflight-"+role)).rglob("handoff-evidence.json"))
        require(len(matches)==1,"missing_handoff_evidence")
        item=json.loads(matches[0].read_text())
        require(item["role"]==role and item["source"]==os.environ["GITHUB_SHA"]
            and item["run"]==os.environ["GITHUB_RUN_ID"] and item["attempt"]==os.environ["GITHUB_RUN_ATTEMPT"]
            and all(item[k] is True for k in ("native_role_read","wrong_role_rejected","wrong_duration_rejected","transient_file_removed"))
            and item["network_used"] is False and item["media_tested"] is False,"invalid_handoff_evidence")
        data.append(item)
    require(data[0]["host_boot_sha256"]!=data[1]["host_boot_sha256"] and
        data[0]["build_sha256"]==data[1]["build_sha256"],"wrong_runner_pair")
    (root/"handoff-validation.json").write_text(json.dumps({"status":"PASS_OFFLINE_NATIVE_ROLE_HANDOFF_ONLY",
        "clients":data,"g03":"BLOCKED"},indent=2)+"\n")
    print("V65_OFFLINE_NATIVE_ROLE_HANDOFF_PAIR=PASS")

if __name__=="__main__":
    try:
        if sys.argv[1:]==["validate"]: validate()
        elif not sys.argv[1:]: rehearse()
        else: raise RuntimeError("invalid_arguments")
    except Exception:
        raise SystemExit("V65_OFFLINE_ROLE_HANDOFF_FAILED")
