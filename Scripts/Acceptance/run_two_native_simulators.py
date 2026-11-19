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
ROOT=Path(os.environ["RUNNER_TEMP"])/"ios173-dual-products"

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def diagnostics(stage):
    # Host resource evidence only; no environments, credentials, or app data.
    for name, cmd in (("memory", ["vm_stat"]), ("disk", ["df", "-h", str(ROOT.parent)]),
                      ("cpu", ["sysctl", "-n", "hw.ncpu"]), ("load", ["sysctl", "-n", "vm.loadavg"])):
        try:
            result=run_bounded(cmd,timeout=10,emit_output=False)
            (OUT/f"{stage}-{name}.txt").write_text(result)
        except RuntimeError as exc:
            (OUT/f"{stage}-{name}.txt").write_text(str(exc))

def reserve():
    # Global inventory is allowed only before booting either test device.
    data=json.loads(run_bounded(["xcrun","simctl","list","devices","available","-j"],timeout=45,emit_output=False))
    matches=[(r,d) for r,rows in data["devices"].items() for d in rows if d["udid"]==FIRST]
    require(len(matches)==1,"missing or ambiguous first simulator")
    runtime,first=matches[0]
    require("iOS-27-0" in runtime and first["name"]=="iPhone 18 Pro Max" and first["state"]=="Shutdown",
            "first simulator must be the selected cold iPhone 18 Pro Max")
    kind=first["deviceTypeIdentifier"]
    second=run_bounded(["xcrun","simctl","create","IOSNext isolated B",kind,runtime],timeout=60,emit_output=False).strip()
    require(re.fullmatch(r"[0-9A-Fa-f-]{36}",second) is not None and FIRST.lower()!=second.lower(),
            "second simulator identity invalid")
    data=json.loads(run_bounded(["xcrun","simctl","list","devices","available","-j"],timeout=45,emit_output=False))
    current={d["udid"]:(r,d) for r,rows in data["devices"].items() for d in rows}
    for uid in (FIRST,second):
        r,d=current[uid]
        require(r==runtime and d["deviceTypeIdentifier"]==kind and d["state"]=="Shutdown",
                "cold reservation does not match requested device/runtime")
    (OUT/"reservation.json").write_text(json.dumps({"runtime":runtime,"device_type":kind,"A":FIRST,"B":second},indent=2)+"\n")
    (OUT/"created-udid.txt").write_text(second+"\n")
    diagnostics("reserved")
    print("IOS180_TWO_DISTINCT_COLD_SIMULATORS_RESERVED",flush=True)

def boot_reserved():
    reservation=json.loads((OUT/"reservation.json").read_text())
    second=reservation["B"]
    require(reservation["A"]==FIRST and FIRST.lower()!=second.lower(),"reservation mismatch")
    timings={}
    for role,uid in (("A",FIRST),("B",second)):
        started=time.monotonic()
        run_bounded(["xcrun","simctl","boot",uid],timeout=60)
        run_bounded(["xcrun","simctl","bootstatus",uid,"-b"],timeout=240)
        timings[role]=round(time.monotonic()-started,3)
        diagnostics(f"boot-{role}")
    # Both bootstatus calls already succeeded. A second bootstatus call
    # stalled in run 44445969729. Check actual guest process execution on
    # both exact destinations concurrently, without reentering bootstatus.
    from concurrent.futures import ThreadPoolExecutor
    def probe(role,uid):
        started=time.monotonic()
        output=run_bounded(["xcrun","simctl","spawn",uid,"launchctl","list"],timeout=90,emit_output=False)
        require("PID" in output and "Label" in output and len(output.splitlines())>1,
                f"guest launchctl did not return a process table for {role}")
        return {"role":role,"udid":uid,"started":started,"finished":time.monotonic(),
                "process_table_rows":len(output.splitlines())-1}
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures=[pool.submit(probe,role,uid) for role,uid in (("A",FIRST),("B",second))]
        probes=[future.result() for future in futures]
    require(max(p["started"] for p in probes)<min(p["finished"] for p in probes),
            "guest probe invocation windows did not overlap")
    (OUT/"simulators.json").write_text(json.dumps({**reservation,"both_booted":True,"boot_seconds":timings,
        "verification":"successful per-device bootstatus followed by overlapping targeted guest process probes",
        "probes":probes},indent=2)+"\n")
    print("IOS173_TWO_DISTINCT_BOOTED_SIMULATORS",flush=True)

def run(second):
    verified=json.loads((OUT/"simulators.json").read_text())
    require(verified["both_booted"] is True and verified["A"]==FIRST and verified["B"]==second and second!=FIRST,"unverified simulator pair")
    SOURCE=Path(os.environ["XCTESTRUN_PATH"]).resolve()
    processes=[]
    streams=[]
    try:
        for role,uid in (("A",FIRST),("B",second)):
            # Separate product directory per xcodebuild, so installation and
            # test-runner preparation cannot alter the other client's bundle.
            products=ROOT/role
            run_bounded(["ditto",str(SOURCE.parent),str(products)],timeout=240)
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
    if sys.argv[1:]==["reserve"]:
        reserve()
    elif sys.argv[1:]==["boot"]:
        boot_reserved()
    elif len(sys.argv)==3 and sys.argv[1]=="run":
        run(sys.argv[2])
    else:
        raise SystemExit("reserve, boot or run SECOND_UDID")
