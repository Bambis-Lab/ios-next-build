"""Run exactly one XCTest in each of two independently booted simulators.
No production credentials or real audio. Fail on any missing/failed evidence.
"""
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
from boot_simulator import run_bounded

OUT=Path("build/ios173/dual-simulator").resolve()
OUT.mkdir(parents=True,exist_ok=True)
FIRST=os.environ["SIM_ID"]
SOURCE=Path(os.environ["XCTESTRUN_PATH"]).resolve()
ROOT=Path(os.environ["RUNNER_TEMP"])/"ios173-dual-products"

def devices():
    data=json.loads(run_bounded(["xcrun","simctl","list","devices","available","-j"],timeout=20,emit_output=False))
    return [(runtime,d) for runtime,rows in data["devices"].items() for d in rows]

def create():
    runtime,first=next((r,d) for r,d in devices() if d["udid"]==FIRST)
    assert "iOS-27-0" in runtime and first["name"]=="iPhone 18 Pro Max" and first["state"]=="Booted"
    kind=first["deviceTypeIdentifier"]
    second=run_bounded(["xcrun","simctl","create","IOSNext isolated B",kind,runtime],timeout=45,emit_output=False).strip()
    assert re.fullmatch(r"[0-9A-Fa-f-]{36}",second) and first["udid"]!=second
    (OUT/"created-udid.txt").write_text(second+"\n")
    run_bounded(["xcrun","simctl","boot",second],timeout=60)
    run_bounded(["xcrun","simctl","bootstatus",second,"-b"],timeout=240)
    current={d["udid"]:(r,d) for r,d in devices()}
    for uid in (FIRST,second):
        r,d=current[uid]
        assert r==runtime and d["deviceTypeIdentifier"]==kind and d["state"]=="Booted"
    (OUT/"simulators.json").write_text(json.dumps({"runtime":runtime,"device_type":kind,"A":FIRST,"B":second,"both_booted":True},indent=2)+"\n")
    print("IOS173_TWO_DISTINCT_BOOTED_SIMULATORS",flush=True)
    return second

def run(second):
    assert second!=FIRST
    processes=[]
    streams=[]
    try:
        for role,uid in (("A",FIRST),("B",second)):
            # Separate product directory per xcodebuild, so installation and
            # test-runner preparation cannot alter the other client's bundle.
            products=ROOT/role
            run_bounded(["ditto",str(SOURCE.parent),str(products)],timeout=180)
        for role,uid in (("A",FIRST),("B",second)):
            test=f"IOSNextTests/FamilyAudioIndependentSimulatorTests/testSimulator{role}"
            log=OUT/f"{role}.log"
            stream=log.open("wb")
            streams.append(stream)
            cmd=["xcodebuild","test-without-building","-collect-test-diagnostics","never",
                 "-xctestrun",str(ROOT/role/SOURCE.name),"-destination",f"platform=iOS Simulator,id={uid}",
                 "-parallel-testing-enabled","NO","-disable-concurrent-destination-testing",
                 "-resultBundlePath",str(OUT/f"{role}.xcresult"),"-only-testing:"+test,
                 "CODE_SIGNING_ALLOWED=YES","CODE_SIGNING_REQUIRED=YES","CODE_SIGN_IDENTITY=-"]
            p=subprocess.Popen(cmd,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
            processes.append((role,uid,p,log))
        deadline=time.monotonic()+1100
        while any(p.poll() is None for _,_,p,_ in processes):
            if any(p.poll() not in (None,0) for _,_,p,_ in processes):
                raise RuntimeError("one native client exited unsuccessfully")
            if time.monotonic()>deadline:
                raise TimeoutError("independent client test deadline")
            time.sleep(.5)
        evidence=[]
        for role,uid,p,log in processes:
            assert p.returncode==0
            text=log.read_text(errors="replace")
            assert re.search(r"\*\* TEST (?:EXECUTE )?SUCCEEDED \*\*",text)
            assert re.search(r"Executed 1 test[s]?, with 0 failures",text)
            match=re.search(r"IOS173_DUAL_RESULT role="+role+r" udid=(\S+) pid=(\d+) sent=(\d+) received=(\d+) elapsed=(\d+)",text)
            assert match, "missing native client evidence"
            observed,pid,sent,received,elapsed=match.groups()
            assert observed in (uid,"unavailable"),"wrong simulator process"
            assert int(sent)==int(received)==30000 and int(elapsed)>=600
            result=run_bounded(["xcrun","xcresulttool","get","test-results","summary","--path",str(OUT/f"{role}.xcresult")],timeout=30,emit_output=False)
            parsed=json.loads(result)
            (OUT/f"{role}-summary.json").write_text(json.dumps(parsed,indent=2)+"\n")
            # Result bundles must independently identify the actual destination.
            assert uid.lower() in result.lower(), "xcresult missing selected simulator UDID"
            evidence.append({"role":role,"destination":uid,"reported_udid":observed,"pid":int(pid),"sent":int(sent),"received":int(received),"elapsed_seconds":int(elapsed)})
        assert evidence[0]["destination"]!=evidence[1]["destination"]
        assert evidence[0]["pid"]!=evidence[1]["pid"],"not independent native processes"
        (OUT/"result.json").write_text(json.dumps({"status":"PASS","scope":"two independent iOS simulators, synthetic 600-second WSS only","real_ha":False,"physical_audio":False,"clients":evidence},indent=2)+"\n")
        print("IOS173_TWO_INDEPENDENT_NATIVE_SIMULATORS=PASS",flush=True)
    finally:
        for _,_,p,_ in processes:
            if p.poll() is None:
                try: os.killpg(p.pid,signal.SIGTERM)
                except ProcessLookupError: pass
        for _,_,p,_ in processes:
            try: p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try: os.killpg(p.pid,signal.SIGKILL)
                except ProcessLookupError: pass
                p.wait(timeout=5)
        for stream in streams: stream.close()

if __name__=="__main__":
    if sys.argv[1:]==["create"]:
        create()
    elif len(sys.argv)==3 and sys.argv[1]=="run":
        run(sys.argv[2])
    else:
        raise SystemExit("create or run SECOND_UDID")
