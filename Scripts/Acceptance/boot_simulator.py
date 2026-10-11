#!/usr/bin/env python3
"""Bound every simulator CLI phase, including discovery and boot itself."""
import json
import os
import signal
import subprocess
import sys
import time

class CommandTimeout(RuntimeError):
    pass

def run_bounded(argv, timeout):
    print(f"SIMULATOR_COMMAND_START timeout={timeout}s cmd={argv[0]}", flush=True)
    child = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, start_new_session=True)
    try:
        output, _ = child.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        print(f"SIMULATOR_COMMAND_TIMEOUT timeout={timeout}s cmd={argv[0]}", flush=True)
        os.killpg(child.pid, signal.SIGTERM)
        try:
            child.wait(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
        raise CommandTimeout(f"Timed out after {timeout}s: {argv[0]}")
    if output:
        print(output[-12000:], end="" if output.endswith("\n") else "\n", flush=True)
    if child.returncode != 0:
        raise RuntimeError(f"Command exited {child.returncode}: {argv[0]}")
    return output

def main():
    device_name = sys.argv[1] if len(sys.argv) > 1 else "iPhone 18 Pro Max"
    runtime_substring = sys.argv[2] if len(sys.argv) > 2 else "iOS-27-0"
    env_file = os.environ.get("GITHUB_ENV")
    started = time.monotonic()
    listing = run_bounded(["xcrun", "simctl", "list", "devices", "available", "-j"], 20)
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

    # A pre-booted simulator is OK; only tolerate the explicit already-booted diagnostic.
    try:
        run_bounded(["xcrun", "simctl", "boot", udid], 20)
    except RuntimeError as exc:
        if "current state: Booted" not in str(exc) and "Booted" not in str(exc):
            # Re-check device state instead of masking arbitrary boot failures.
            latest = json.loads(run_bounded(["xcrun", "simctl", "list", "devices", "available", "-j"], 10))
            states = [d.get("state") for devs in latest.get("devices", {}).values() for d in devs if d.get("udid") == udid]
            if not states or states[0] != "Booted":
                raise

    run_bounded(["xcrun", "simctl", "bootstatus", udid, "-b"], 60)
    if env_file:
        with open(env_file, "a", encoding="utf-8") as stream:
            stream.write(f"SIM_ID={udid}\n")
    print(f"SIMULATOR_READY udid={udid} elapsed={time.monotonic()-started:.1f}s", flush=True)
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"SIMULATOR_BOOT_FAILED: {error}", file=sys.stderr, flush=True)
        raise SystemExit(1)
