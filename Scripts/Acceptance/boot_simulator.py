#!/usr/bin/env python3
"""Boot a named iOS Simulator with bounded process-group cleanup."""
import json
import os
import signal
import subprocess
import sys
import time


def run_bounded(argv, timeout=90, *, emit_output=True):
    print(f"SIMULATOR_COMMAND_START timeout={timeout}s cmd={argv[0]}", flush=True)
    process = subprocess.Popen(
        argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, start_new_session=True
    )
    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        print(f"SIMULATOR_COMMAND_TIMEOUT cmd={argv[0]} timeout={timeout}s", flush=True)
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            output, _ = process.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                # Never perform an unbounded communicate() after SIGKILL.
                output, _ = process.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                # A descendant may still hold the pipe open. Close our side
                # and bound reaping so this watchdog cannot stall the whole job.
                if process.stdout is not None:
                    process.stdout.close()
                try:
                    process.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    pass
                output = ""
        if output and emit_output:
            print(output, end="" if output.endswith("\n") else "\n", flush=True)
        raise RuntimeError(f"Command timed out after {timeout}s: {argv[0]}")
    if output and emit_output:
        print(output, end="" if output.endswith("\n") else "\n", flush=True)
    if process.returncode != 0:
        raise RuntimeError(f"Command exited {process.returncode}: {argv[0]}")
    return output or ""


def main():
    device_name = sys.argv[1] if len(sys.argv) > 1 else "iPhone 18 Pro Max"
    runtime_substring = sys.argv[2] if len(sys.argv) > 2 else "iOS-27-0"
    env_file = os.environ.get("GITHUB_ENV")
    started = time.monotonic()

    listing = run_bounded(["xcrun", "simctl", "list", "devices", "available", "-j"], timeout=15, emit_output=False)
    data = json.loads(listing)
    matches = [
        (runtime, device) for runtime, devices in data.get("devices", {}).items()
        if runtime_substring in runtime
        for device in devices
        if device.get("name") == device_name and device.get("isAvailable", True)
    ]
    if not matches:
        raise RuntimeError(f"No available {device_name} simulator for {runtime_substring}")

    runtime, device = matches[0]
    udid = device["udid"]
    print(f"SIMULATOR_SELECTED runtime={runtime} name={device_name} udid={udid}", flush=True)

    # Expose the selected destination before any boot attempt. Compile-only
    # gates can build against a shutdown simulator; Xcode owns test-time boot.
    if env_file:
        with open(env_file, "a", encoding="utf-8") as stream:
            stream.write(f"SIM_ID={udid}\n")
    if "--resolve-only" in sys.argv[3:]:
        print(f"SIMULATOR_DESTINATION_RESOLVED udid={udid}", flush=True)
        return 0

    try:
        run_bounded(["xcrun", "simctl", "boot", udid], timeout=30)
    except RuntimeError as exc:
        latest = json.loads(run_bounded(
            ["xcrun", "simctl", "list", "devices", "available", "-j"], timeout=15, emit_output=False
        ))
        states = [d.get("state") for devs in latest.get("devices", {}).values()
                  for d in devs if d.get("udid") == udid]
        if not states or states[0] != "Booted":
            raise exc

    run_bounded(["xcrun", "simctl", "bootstatus", udid, "-b"], timeout=90)
    print(f"SIMULATOR_READY udid={udid} elapsed={time.monotonic()-started:.1f}s", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"SIMULATOR_BOOT_FAILED: {error}", file=sys.stderr, flush=True)
        raise SystemExit(1)
