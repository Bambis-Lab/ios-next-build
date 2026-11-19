"""Operator-invoked native media stage on an already authorized test route.

Requires a freshly allocated disposable GitHub-hosted macOS simulator,
verified build products and a privately provisioned role file. This script
never starts a tunnel, provisioner, external relay or production service.
The role file MUST be supplied after runner boot because its grants expire.
Original logs/results remain in a private directory, not auto-uploaded.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from boot_simulator import run_bounded
from native_role_handoff import read_private,validate,install_role,relay_fingerprint,require
from validate_distributed_media import HEX, SHA, UUID

def extract(log,summary,role,duration,uid,expected_relay):
    require(re.search(r"\*\* TEST (?:EXECUTE )?SUCCEEDED \*\*",log) is not None and
            re.search(r"Executed 1 test[s]?, with 0 failures",log) is not None,"native_test_failed")
    require(uid.lower() in summary.lower(),"xcresult_missing_destination")
    matches=re.findall(r"V64_NATIVE_MEDIA role=([AB]) sent=(\d+) received=(\d+) renewals=(\d+) elapsed=([0-9.]+) started=([0-9.]+) finished=([0-9.]+) relay=([0-9a-f]{64})",log)
    require(len(matches)==1,"missing_or_duplicate_native_marker")
    observed,sent,received,renewals,elapsed,started,finished,relay=matches[0]
    require(observed==role and int(sent)==int(received)==duration*50 and int(renewals)==2 and relay==expected_relay,
            "native_media_mismatch")
    process=re.findall(r"IOS173_DUAL_RESULT role="+role+r" udid=(\S+) pid=(\d+) sent=(\d+) received=(\d+) elapsed=(\d+)",log)
    require(len(process)==1 and process[0][0] in (uid,"unavailable") and
            int(process[0][2])==int(process[0][3])==duration*50,"native_process_mismatch")
    return {"role":role,"pid":int(process[0][1]),"sent":int(sent),"received":int(received),
            "renewals":int(renewals),"elapsed_seconds":float(elapsed),"media_started_utc":float(started),
            "media_finished_utc":float(finished),"relay_session_sha256":relay}

def run(role,duration,role_path):
    require(os.environ.get("GITHUB_ACTIONS")=="true" and os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted",
            "disposable_hosted_runner_required")
    # This is an invocation guard, not an authorization provider.
    require(os.environ.get("IOSNEXT_APPROVED_TEST_ROUTE")=="operator-confirmed-isolated-test-only",
            "explicit_approved_test_route_required")
    require(role in ("A","B") and duration in (30,120,300),"invalid_stage")
    uid=os.environ["SIM_ID"]
    source=os.environ["GITHUB_SHA"]
    run_id=os.environ["GITHUB_RUN_ID"]
    attempt=os.environ["GITHUB_RUN_ATTEMPT"]
    require(UUID.fullmatch(uid) and SHA.fullmatch(source) and run_id.isdecimal() and attempt.isdecimal(),"invalid_run_identity")
    root=Path(os.environ["RUNNER_TEMP"]).resolve(strict=True)
    output=root/("iosnext-v64-private-native-"+role+"-"+str(duration))
    output.mkdir(mode=0o700,exist_ok=False)
    # Private outputs deliberately do not enter build/** artifact globs.
    handoff=Path("build/ios173/handoff")
    manifest=(handoff/"source-and-duration.txt").read_text().splitlines()
    require(manifest==[source,str(duration)],"build_stage_mismatch")
    archive=handoff/"products.zip"
    with archive.open("rb") as f:
        digest=hashlib.file_digest(f,"sha256").hexdigest()
    expected=(handoff/"SHA256SUMS").read_text().split()
    require(expected==[digest,"products.zip"],"build_digest_mismatch")
    require((handoff/"xcode-version.txt").read_text().strip()==run_bounded(["xcodebuild","-version"],timeout=20,emit_output=False).strip(),"xcode_mismatch")
    require((handoff/"architecture.txt").read_text().strip()==run_bounded(["uname","-m"],timeout=10,emit_output=False).strip(),"architecture_mismatch")
    products=output/"products"
    products.mkdir(mode=0o700)
    run_bounded(["ditto","-x","-k",str(archive.resolve()),str(products)],timeout=240,emit_output=False)
    candidates=list(products.glob("Products/*.xctestrun"))
    apps=list(products.glob("Products/Debug-iphonesimulator/IOSNext.app"))
    require(len(candidates)==1 and len(apps)==1,"unexpected_products_layout")
    inventory=json.loads(run_bounded(["xcrun","simctl","list","devices","available","-j"],timeout=30,emit_output=False))
    matches=[(r,d) for r,ds in inventory["devices"].items() for d in ds if d["udid"]==uid]
    require(len(matches)==1 and "iOS-27-0" in matches[0][0] and
            matches[0][1]["name"]=="iPhone 18 Pro Max" and matches[0][1]["state"]=="Booted","wrong_or_cold_simulator")
    # Refuse an already installed app, even in a hosted environment. This
    # prevents writing the role contract into a prior user/test profile.
    bundle="de.nicofroeba16.iosnext"
    installed=json.loads(run_bounded(["xcrun","simctl","listapps",uid,"--json"],timeout=30,emit_output=False))
    require(bundle not in installed,"existing_app_container")
    run_bounded(["xcrun","simctl","install",uid,str(apps[0])],timeout=90,emit_output=False)
    container=Path(run_bounded(["xcrun","simctl","get_app_container",uid,bundle,"data"],timeout=30,emit_output=False).strip())
    raw=read_private(role_path)
    item=validate(raw,role,duration)
    target=install_role(raw,container,role,duration)
    try:
        result=output/(role+".xcresult")
        log=run_bounded(["xcodebuild","test-without-building","-collect-test-diagnostics","never",
             "-xctestrun",str(candidates[0]),"-destination","platform=iOS Simulator,id="+uid,
             "-parallel-testing-enabled","NO","-disable-concurrent-destination-testing",
             "-resultBundlePath",str(result),"-only-testing:IOSNextTests/FamilyAudioIndependentSimulatorTests/testDistributed"+role,
             "CODE_SIGNING_ALLOWED=YES","CODE_SIGNING_REQUIRED=YES","CODE_SIGN_IDENTITY=-"],
             timeout=duration+500,emit_output=False)
        summary=run_bounded(["xcrun","xcresulttool","get","test-results","summary","--path",str(result)],timeout=60,emit_output=False)
        evidence=extract(log,summary,role,duration,uid,relay_fingerprint(item))
        boot=run_bounded(["sysctl","-n","kern.bootsessionuuid"],timeout=10,emit_output=False).strip()
        require(UUID.fullmatch(boot),"invalid_host_boot_session")
        evidence.update({"version":1,"source":source,"run":run_id,"attempt":attempt,
            "duration":duration,"build_sha256":digest,"host_boot_sha256":hashlib.sha256(boot.encode()).hexdigest(),
            "simulator":uid,"xcresult_device":uid,"test_name":"testDistributed"+role,"test_pass":True,"physical_audio":False})
        # Raw diagnostic data stays private. Only a validated, explicitly
        # reviewed safe subset may be copied into a CI artifact.
        for name,content in (("native.log",log),("summary.json",summary),("native-evidence.json",json.dumps(evidence,indent=2))):
            fd=os.open(output/name,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
            with os.fdopen(fd,"w",encoding="utf-8") as stream: stream.write(content)
        print("V64_NATIVE_STAGE_EVIDENCE_READY",flush=True)
    finally:
        # Only remove the exact transient role file created by this invocation.
        # No app data, history, original evidence or simulator is erased.
        target.unlink(missing_ok=True)

if __name__=="__main__":
    if len(sys.argv)!=4: raise SystemExit("usage: run_distributed_native_role.py A|B DURATION PRIVATE_ROLE_FILE")
    try: run(sys.argv[1],int(sys.argv[2]),sys.argv[3])
    except Exception:
        # Underlying errors may contain private paths or request metadata.
        raise SystemExit("V64_NATIVE_STAGE_FAILED; inspect restricted local evidence")
