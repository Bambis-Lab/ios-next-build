#!/usr/bin/env python3
"""Boot a named iOS Simulator with bounded process-group cleanup."""
import json
import os
import signal
import subprocess
import sys
import time


def signal_owned_process(process, sig):
    """Best-effort cleanup of our child only, never kill unrelated processes."""
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, sig)
    except ProcessLookupError:
        return
    except PermissionError:
        # Some hosted macOS sandboxes deny process-group signalling even
        # for a child. Fall back to the original child's process handle.
        print("SIMULATOR_GROUP_SIGNAL_DENIED", flush=True)
        try:
            process.send_signal(sig)
        except (ProcessLookupError, PermissionError):
            print("SIMULATOR_CHILD_SIGNAL_UNAVAILABLE", flush=True)


def terminate_owned_process(process):
    """Bounded cleanup; never replace the original error with cleanup EPERM."""
    for sig in (signal.SIGTERM, signal.SIGKILL):
        signal_owned_process(process, sig)
        try:
            process.wait(timeout=3)
            return True
        except subprocess.TimeoutExpired:
            pass
    print("SIMULATOR_CHILD_REAP_UNCONFIRMED", flush=True)
    return False


def run_bounded(argv, timeout=90, *, emit_output=True):
    print(f"SIMULATOR_COMMAND_START timeout={timeout}s cmd={argv[0]}", flush=True)
    process = subprocess.Popen(
        argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, start_new_session=True
    )
    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        print(f"SIMULATOR_COMMAND_TIMEOUT cmd={argv[0]} timeout={timeout}s", flush=True)
        # Close our read end even if a descendant inherited the pipe. No
        # unbounded communicate and no attempt to elevate permissions.
        if process.stdout is not None:
            process.stdout.close()
        reaped = terminate_owned_process(process)
        raise RuntimeError(f"Command timed out after {timeout}s: {argv[0]}; child_reaped={reaped}") from exc
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

    # iOS 27 migration may exceed 90s on cold self-hosted runners.
    # Explicit opt-in per acceptance job; the default stays 90s elsewhere.
    bootstatus_timeout = int(os.environ.get("IOSNEXT_BOOTSTATUS_TIMEOUT_SECONDS", "90"))
    if not 30 <= bootstatus_timeout <= 240:
        raise RuntimeError("Invalid IOSNEXT_BOOTSTATUS_TIMEOUT_SECONDS (30..240)")
    run_bounded(["xcrun", "simctl", "bootstatus", udid, "-b"], timeout=bootstatus_timeout)
    print(f"SIMULATOR_READY udid={udid} elapsed={time.monotonic()-started:.1f}s", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"SIMULATOR_BOOT_FAILED: {error}", file=sys.stderr, flush=True)
        raise SystemExit(1)
