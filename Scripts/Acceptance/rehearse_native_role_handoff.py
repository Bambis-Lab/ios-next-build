"""Rehearse role-file handoff on hosted iOS simulator; no relay or sockets."""
import json
import os
from pathlib import Path
import sys
from boot_simulator import run_bounded

_stage="startup"
_SAFE_REASONS=frozenset({
    "disposable_host_required","wrong_role","missing_current_native_preflight",
    "native_role_read_failed","wrong_result_destination","role_file_changed",
    "sensitive_output_detected","cleanup_failed","missing_handoff_evidence",
    "invalid_handoff_evidence","wrong_runner_pair","invalid_arguments",
    "sandbox_changed","invalid_container","unsafe_container_directory",
    "container_escape","invalid_expiry","invalid_grant_expiry",
    "xcresult_missing","xcresult_wrong_test","xcresult_test_not_passed",
    "native_command_failed","native_marker_missing","xcresult_invalid_schema",
})

class HandoffError(RuntimeError):
    pass

def stage(name):
    global _stage
    _stage=name
    print("V66_HANDOFF_STAGE="+name,flush=True)

def require(ok,reason):
    if not ok: raise HandoffError(reason)

def safe_failure(error):
    # Never emit exception messages, paths, subprocess output or role data.
    reason=next((x for x in _SAFE_REASONS if error.args==(x,)),None)
    if reason is None:
        if isinstance(error,FileNotFoundError): reason="file_missing"
        elif isinstance(error,FileExistsError): reason="file_already_exists"
        elif isinstance(error,PermissionError): reason="permission_denied"
        elif isinstance(error,KeyError): reason="required_field_missing"
        elif isinstance(error,json.JSONDecodeError): reason="invalid_json"
        elif isinstance(error,RuntimeError): reason="runtime_or_command_failure"
        else: reason="unexpected_failure"
    return reason

def test_cases(node):
    if isinstance(node,list):
        for child in node:
            yield from test_cases(child)
    elif isinstance(node,dict):
        if node.get("nodeType")=="Test Case":
            yield node
        else:
            yield from test_cases(node.get("children",[]))

def native_result_status(tree,role):
    require(isinstance(tree,dict) and isinstance(tree.get("testNodes"),list),
            "xcresult_invalid_schema")
    cases=list(test_cases(tree["testNodes"]))
    expected="FamilyAudioIndependentSimulatorTests/testOfflineRoleHandoff"+role
    ids={expected,expected+"()","IOSNextTests/"+expected,"IOSNextTests/"+expected+"()"}
    exact=[item for item in cases if item.get("nodeIdentifier") in ids]
    if len(cases)!=1 or len(exact)!=1: return "WRONG_TEST"
    return "PASS" if exact[0].get("result")=="Passed" else "NOT_PASSED"

def inspect_result(result,out,role,uid):
    stage("read_xcresult")
    require(result.is_dir(),"xcresult_missing")
    summary=run_bounded(["xcrun","xcresulttool","get","test-results","summary","--path",str(result)],
        timeout=60,emit_output=False)
    tree=run_bounded(["xcrun","xcresulttool","get","test-results","tests","--path",str(result)],
        timeout=60,emit_output=False)
    status=native_result_status(json.loads(tree),role)
    destination=uid.lower() in summary.lower()
    # Export only fixed status fields, not raw logs, exception text or JSON.
    (out/"handoff-result-status.json").write_text(json.dumps({
        "role":role,"test_status":status,"destination_matches":destination,
        "run":os.environ["GITHUB_RUN_ID"],"attempt":os.environ["GITHUB_RUN_ATTEMPT"],
        "source":os.environ["GITHUB_SHA"]},indent=2)+"\n")
    require(destination,"wrong_result_destination")
    require(status!="WRONG_TEST","xcresult_wrong_test")
    require(status=="PASS","xcresult_test_not_passed")
    return summary,tree

def rehearse():
    stage("import_dependencies")
    from distributed_role_provisioning import generate
    from native_role_handoff import install_role, read_private
    stage("authorize_disposable_host")
    require(os.environ.get("GITHUB_ACTIONS")=="true" and
            os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted","disposable_host_required")
    role=os.environ["IOSNEXT_PREFLIGHT_ROLE"]
    uid=os.environ["SIM_ID"]
    require(role in ("A","B"),"wrong_role")
    out=Path("build/ios173/dual-simulator")
    stage("verify_preflight")
    pre=json.loads((out/"preflight.json").read_text())
    require(pre["role"]==role and pre["simulator"]==uid and pre["native_test_pass"] is True
            and pre["source"]==os.environ["GITHUB_SHA"] and pre["run"]==os.environ["GITHUB_RUN_ID"]
            and pre["attempt"]==os.environ["GITHUB_RUN_ATTEMPT"],"missing_current_native_preflight")
    # The successful prerequisite already installed this disposable test app.
    # Locate only its sandbox; do not touch any existing real user profile.
    stage("resolve_app_container")
    container=Path(run_bounded(["xcrun","simctl","get_app_container",uid,
         "de.nicofroeba16.iosnext","data"],timeout=30,emit_output=False).strip())
    stage("generate_offline_contract")
    _,roles=generate(os.environ["GITHUB_RUN_ID"]+":"+os.environ["GITHUB_RUN_ATTEMPT"],
        30,"https://fixture.invalid/")
    raw=json.dumps(roles[role],separators=(",",":")).encode("ascii")
    stage("install_private_role")
    target=install_role(raw,container,role,30)
    result=out/("role-"+role+".xcresult")
    try:
        stage("run_native_xctest")
        command_failed=False
        log=""
        try:
            log=run_bounded(["xcodebuild","test-without-building","-collect-test-diagnostics","never",
            "-xctestrun",str(Path(os.environ["XCTESTRUN_PATH"]).resolve()),"-destination","platform=iOS Simulator,id="+uid,
            "-parallel-testing-enabled","NO","-disable-concurrent-destination-testing",
            "-resultBundlePath",str(result.resolve()),
            "-only-testing:IOSNextTests/FamilyAudioIndependentSimulatorTests/testOfflineRoleHandoff"+role,
            "CODE_SIGNING_ALLOWED=YES","CODE_SIGNING_REQUIRED=YES","CODE_SIGN_IDENTITY=-"],
                timeout=480,emit_output=False)
        except RuntimeError:
            command_failed=True
            print("V66_NATIVE_COMMAND=FAIL",flush=True)
        # A failed xcodebuild may still produce an authoritative result bundle.
        # Record its sanitized test status even when the command failed.
        summary,tree=inspect_result(result,out,role,uid)
        stage("verify_native_command")
        require(not command_failed,"native_command_failed")
        stage("verify_native_marker")
        require(log.count("V65_OFFLINE_NATIVE_ROLE_HANDOFF=PASS role="+role)==1,
                "native_marker_missing")
        stage("verify_sandbox_identity")
        current=Path(run_bounded(["xcrun","simctl","get_app_container",uid,
            "de.nicofroeba16.iosnext","data"],timeout=30,emit_output=False).strip())
        require(current.resolve()==container.resolve(),"sandbox_changed")
        stage("verify_private_role_integrity")
        require(target.is_file() and read_private(target)==raw,"role_file_changed")
        # Never publish a source role file or any bearer/key material.
        stage("verify_output_privacy")
        require(all(x not in log and x not in summary and x not in tree
                    for x in roles[role]["tokens"]+[roles[role]["signingSeed"]]),
                "sensitive_output_detected")
        # The sanitized structured status is sufficient; do not duplicate raw summary.
    finally:
        # Keep the failing phase visible when cleanup succeeds.
        try:
            target.unlink(missing_ok=True)
            require(not target.exists(),"cleanup_failed")
        except Exception:
            print("V66_HANDOFF_CLEANUP=FAIL",file=sys.stderr,flush=True)
            raise
        print("V66_HANDOFF_CLEANUP=PASS",flush=True)
    stage("write_handoff_evidence")
    (out/"handoff-evidence.json").write_text(json.dumps({"role":role,"source":pre["source"],
        "run":pre["run"],"attempt":pre["attempt"],"simulator":uid,
        "build_sha256":pre["build_sha256"],"host_boot_sha256":pre["boot_session_sha256"],
        "native_role_read":True,"wrong_role_rejected":True,"wrong_duration_rejected":True,
        "transient_file_removed":True,"network_used":False,"media_tested":False},indent=2)+"\n")
    print("V65_OFFLINE_ROLE_HANDOFF_COMPLETE role="+role)

def self_test():
    import unittest
    class ResultValidation(unittest.TestCase):
        def tree(self,role="A",status="Passed"):
            return {"testNodes":[{"nodeType":"Test Suite","children":[
                {"nodeType":"Test Case","nodeIdentifier":
                 "FamilyAudioIndependentSimulatorTests/testOfflineRoleHandoff"+role+"()",
                 "result":status}]}]}
        def test_exact_role(self):
            for role in ("A","B"):
                self.assertEqual(native_result_status(self.tree(role),role),"PASS")
        def test_wrong_role(self):
            self.assertEqual(native_result_status(self.tree("B"),"A"),"WRONG_TEST")
        def test_failed_skipped_expected_failure(self):
            for status in ("Failed","Skipped","Expected Failure","Unknown"):
                self.assertEqual(native_result_status(self.tree(status=status),"A"),"NOT_PASSED")
        def test_empty_duplicate_or_extra_case(self):
            tree=self.tree()
            tree["testNodes"]*=2
            self.assertEqual(native_result_status(tree,"A"),"WRONG_TEST")
            self.assertEqual(native_result_status({"testNodes":[]},"A"),"WRONG_TEST")
        def test_invalid_schema(self):
            with self.assertRaises(HandoffError):
                native_result_status({},"A")
    suite=unittest.defaultTestLoader.loadTestsFromTestCase(ResultValidation)
    if not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful():
        raise SystemExit(1)

def validate():
    stage("validate_pair")
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
        elif sys.argv[1:]==["self-test"]: self_test()
        elif not sys.argv[1:]: rehearse()
        else: raise RuntimeError("invalid_arguments")
    except Exception as error:
        print("V66_HANDOFF_FAILURE stage="+_stage+" reason="+safe_failure(error),file=sys.stderr,flush=True)
        raise SystemExit("V65_OFFLINE_ROLE_HANDOFF_FAILED") from None
