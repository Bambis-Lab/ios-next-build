#!/usr/bin/env python3
"""Run bounded Xcode tests and verify result bundles after Xcode cleanup hangs.

A watchdog timeout is accepted only if xcodebuild explicitly reports successful
test execution AND xcresulttool confirms a finished result with zero failures
and every test accounted for. Any missing/ambiguous evidence stays red.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import threading


def first_value(data, names):
    if isinstance(data, dict):
        for name in names:
            value = data.get(name)
            if value is not None:
                return value
        for value in data.values():
            found = first_value(value, names)
            if found is not None:
                return found
    elif isinstance(data, list):
        for value in data:
            found = first_value(value, names)
            if found is not None:
                return found
    return None


def verify_summary(summary):
    result = first_value(summary, ("result", "status"))
    total = first_value(summary, ("totalTestCount", "totalTests"))
    passed = first_value(summary, ("passedTests", "passedTestCount"))
    failed = first_value(summary, ("failedTests", "failedTestCount"))
    skipped = first_value(summary, ("skippedTests", "skippedTestCount"))
    finish = first_value(summary, ("finishTime", "finishedAt", "endTime"))
    if not isinstance(result, str) or result.strip().lower() not in {"passed", "success", "succeeded"}:
        return False, "xcresult has no successful final result"
    if not isinstance(total, int) or total < 1:
        return False, "xcresult has no valid total test count"
    if not isinstance(passed, int) or not isinstance(failed, int):
        return False, "xcresult is missing passed/failed counts"
    if skipped is None:
        skipped = 0
    if not isinstance(skipped, int) or failed != 0 or passed + skipped != total:
        return False, "xcresult counts show failure or incomplete accounting"
    if not isinstance(finish, (str, int, float)) or not finish:
        return False, "xcresult has no finished timestamp"
    return True, f"result={result} total={total} passed={passed} skipped={skipped} failed={failed}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout-seconds", type=int, required=True)
    parser.add_argument("--result-bundle", required=True)
    parser.add_argument("--log-file", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("missing xcodebuild command after --")

    log_path = Path(args.log_file)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"XCODE_VERIFIED_RUN_START timeout={args.timeout_seconds}s", flush=True)
    captured = []
    with log_path.open("w", encoding="utf-8") as log:
        proc = subprocess.Popen(
            [sys.executable, "Scripts/Acceptance/xcode_watchdog.py",
             "--timeout-seconds", str(args.timeout_seconds), "--", *command],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace"
        )
        assert proc.stdout is not None

        def relay_output():
            for line in proc.stdout:
                captured.append(line)
                sys.stdout.write(line)
                sys.stdout.flush()
                log.write(line)
                log.flush()

        reader = threading.Thread(target=relay_output, daemon=True)
        reader.start()
        code = proc.wait()
        reader.join(timeout=10)

    if code == 0:
        print("XCODE_VERIFIED_RUN=PASS (xcodebuild exited successfully)", flush=True)
        return 0
    if code != 124:
        print(f"XCODE_VERIFIED_RUN=FAIL xcodebuild_exit={code}", flush=True)
        return code

    log_text = "".join(captured)
    if "** TEST EXECUTE SUCCEEDED **" not in log_text or "** TEST EXECUTE FAILED **" in log_text:
        print("XCODE_VERIFIED_RUN=FAIL timeout without explicit successful test completion", flush=True)
        return 124

    bundle = Path(args.result_bundle)
    if not bundle.is_dir():
        print("XCODE_VERIFIED_RUN=FAIL result bundle missing", flush=True)
        return 124
    try:
        summary_proc = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "summary",
             "--path", str(bundle), "--format", "json"],
            capture_output=True, text=True, timeout=30
        )
    except subprocess.TimeoutExpired:
        print("XCODE_VERIFIED_RUN=FAIL xcresulttool timed out", flush=True)
        return 124
    if summary_proc.returncode != 0:
        print("XCODE_VERIFIED_RUN=FAIL xcresulttool summary unavailable", flush=True)
        print(summary_proc.stderr[-4000:], flush=True)
        return 124
    try:
        summary = json.loads(summary_proc.stdout)
    except json.JSONDecodeError:
        print("XCODE_VERIFIED_RUN=FAIL xcresulttool output was not JSON", flush=True)
        return 124

    ok, details = verify_summary(summary)
    if not ok:
        print(f"XCODE_VERIFIED_RUN=FAIL {details}", flush=True)
        return 124
    print("XCODE_VERIFIED_RUN=PASS_WITH_CLEANUP_TIMEOUT", flush=True)
    print("XCODE_CLEANUP_TIMEOUT_NOTE=explicit successful test execution plus independently verified finished xcresult; no test failures.", flush=True)
    print(f"XCODE_RESULT_EVIDENCE {details}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
