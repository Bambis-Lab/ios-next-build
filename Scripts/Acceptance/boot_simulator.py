#!/usr/bin/env python3
"""Start an iOS Simulator with bounded subprocess calls and precise diagnostics."""
import json
import os
import subprocess
import sys
import time


def run_unbounded(argv):
    print(f"SIMULATOR_COMMAND_START cmd={argv[0]} args={argv[1:]}", flush=True)
    completed = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, check=False)
    if completed.stdout:
        print(completed.stdout, end="" if completed.stdout.endswith("\n") else "\n", flush=True)
    if completed.returncode != 0:
        raise RuntimeError(f"Command exited {completed.returncode}: {argv[0]}")
    return completed.stdout or ""


def main():
    device_name = sys.argv[1] if len(sys.argv) > 1 else "iPhone 18 Pro Max"
    runtime_substring = sys.argv[2] if len(sys.argv) > 2 else "iOS-27-0"
    env_file = os.environ.get("GITHUB_ENV")
    started = time.monotonic()

    listing = run_bounded(["xcrun", "simctl", "list", "devices", "available", "-j"], timeout=45)
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

    try:
        run_unbounded(["xcrun", "simctl", "boot", udid])
    except RuntimeError as exc:
        # Only suppress boot failure if querying CoreSimulator confirms it is
        # already booted; otherwise preserve the underlying error.
        latest = json.loads(run_unbounded(["xcrun", "simctl", "list", "devices", "available", "-j"]))
        states = [d.get("state") for devs in latest.get("devices", {}).values()
                  for d in devs if d.get("udid") == udid]
        if not states or states[0] != "Booted":
            raise exc

    run_unbounded(["xcrun", "simctl", "bootstatus", udid, "-b"])
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
