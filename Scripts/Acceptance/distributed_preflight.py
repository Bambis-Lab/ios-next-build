"""V6.4 distributed preflight only. Never claims media or G03 success."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
from boot_simulator import run_bounded

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def client():
    role=os.environ["IOSNEXT_PREFLIGHT_ROLE"]
    require(role in ("A","B"),"invalid role")
    uid=os.environ["SIM_ID"]
    out=Path("build/ios173/dual-simulator")
    boot=run_bounded(["sysctl","-n","kern.bootsessionuuid"],timeout=10,emit_output=False).strip()
    require(re.fullmatch(r"[0-9a-fA-F-]{36}",boot) is not None,"missing boot identity")
    build=(out/"SHA256SUMS").read_text().split()[0]
    require(re.fullmatch(r"[0-9a-f]{64}",build) is not None,"missing build checksum")
    started=time.time()
    # The previous launchctl inventory timed out even after bootstatus passed.
    # Use stronger evidence: actually execute a targeted XCTest in the guest.
    # Record the optional inventory failure without skipping the native gate.
    try:
        table=run_bounded(["xcrun","simctl","spawn",uid,"launchctl","list"],timeout=20,emit_output=False)
        inventory="PASS" if "PID" in table and "Label" in table else "INVALID"
    except RuntimeError:
        inventory="TIMEOUT_OR_ERROR"
    (out/"guest-inventory-status.txt").write_text(inventory+"\n")
    result=out/(role+".xcresult")
    log=run_bounded(["xcodebuild","test-without-building","-collect-test-diagnostics","never",
        "-xctestrun",str(Path(os.environ["XCTESTRUN_PATH"]).resolve()),"-destination","platform=iOS Simulator,id="+uid,
        "-parallel-testing-enabled","NO","-disable-concurrent-destination-testing",
        "-resultBundlePath",str(result.resolve()),
        "-only-testing:IOSNextTests/FamilyAudioIndependentSimulatorTests/testNativeExecutionPrerequisite",
        "CODE_SIGNING_ALLOWED=YES","CODE_SIGNING_REQUIRED=YES","CODE_SIGN_IDENTITY=-"],timeout=480)
    (out/"native-test.log").write_text(log)
    require("V64_NATIVE_EXECUTION_PREREQUISITE=PASS" in log and
        re.search(r"Executed 1 test[s]?, with 0 failures",log) is not None and
        re.search(r"\*\* TEST (?:EXECUTE )?SUCCEEDED \*\*",log) is not None,"native test not proven")
    summary=run_bounded(["xcrun","xcresulttool","get","test-results","summary","--path",str(result)],timeout=60,emit_output=False)
    require(uid.lower() in summary.lower(),"xcresult missing exact destination")
    (out/"native-summary.json").write_text(summary)
    evidence={"role":role,"source":os.environ["GITHUB_SHA"],"run":os.environ["GITHUB_RUN_ID"],
              "attempt":os.environ["GITHUB_RUN_ATTEMPT"],"simulator":uid,"build_sha256":build,
              "boot_session_sha256":hashlib.sha256(boot.encode()).hexdigest(),
              "native_test_pass":True,"guest_inventory_status":inventory,"probe_started_utc":started,
              "probe_finished_utc":time.time(),"media_tested":False,"relay_reachable":False}
    (out/"preflight.json").write_text(json.dumps(evidence,indent=2)+"\n")
    print("V64_DISTINCT_RUNNER_PREREQUISITE="+role)

def validate():
    root=Path("build/preflight")
    clients=[]
    for role in ("A","B"):
        files=list((root/("V64-preflight-"+role)).rglob("preflight.json"))
        require(len(files)==1,"missing role evidence "+role)
        item=json.loads(files[0].read_text())
        require(item["role"]==role and item["source"]==os.environ["GITHUB_SHA"] and
                item["run"]==os.environ["GITHUB_RUN_ID"] and item["attempt"]==os.environ["GITHUB_RUN_ATTEMPT"]
                and item["native_test_pass"] is True and item["media_tested"] is False
                and item["relay_reachable"] is False,"invalid role evidence")
        clients.append(item)
    a,b=clients
    require(a["build_sha256"]==b["build_sha256"],"different build products")
    require(a["boot_session_sha256"]!=b["boot_session_sha256"],"not independent execution sessions")
    # Hosted images may reuse the same template simulator UDID on separate
    # machines. The host boot-session plus UDID forms the destination identity.
    result={"status":"PASS_PREREQUISITE_ONLY","clients":clients,
            "relay_status":"NOT_CONFIGURED_OR_TESTED","g03":"BLOCKED",
            "probe_windows_overlap":max(x["probe_started_utc"] for x in clients)<min(x["probe_finished_utc"] for x in clients)}
    (root/"validation.json").write_text(json.dumps(result,indent=2)+"\n")
    print("V64_DISTRIBUTED_RUNNER_PREREQUISITE=PASS; G03=BLOCKED")

if __name__=="__main__":
    if sys.argv[1:]==["client"]: client()
    elif sys.argv[1:]==["validate"]: validate()
    else: raise SystemExit("client or validate")
