#!/usr/bin/env python3
"""Bounded, process-group-aware runner command. Reports exits; never masks failures.

Usage: python3 xcode_watchdog.py --timeout-seconds 240 -- xcodebuild ...
Runs on macOS without installing GNU timeout. On timeout the entire child
process group is terminated so xcodebuild's diagnostic hang cannot outlive CI.
"""
import argparse
import os
import signal
import subprocess
import sys
import time

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout-seconds", type=int, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.timeout_seconds < 1:
        parser.error("timeout must be positive")
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("missing command after --")
    started = time.monotonic()
    print(f"XCODE_WATCHDOG_START timeout={args.timeout_seconds}s command={command[0]}", flush=True)
    child = subprocess.Popen(command, start_new_session=True)
    try:
        code = child.wait(timeout=args.timeout_seconds)
    except subprocess.TimeoutExpired:
        print(f"XCODE_WATCHDOG_TIMEOUT elapsed={time.monotonic()-started:.1f}s", flush=True)
        os.killpg(child.pid, signal.SIGTERM)
        try:
            child.wait(timeout=8)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
        return 124
    print(f"XCODE_WATCHDOG_EXIT code={code} elapsed={time.monotonic()-started:.1f}s", flush=True)
    return code if code >= 0 else 128 - code

if __name__ == "__main__":
    sys.exit(main())
