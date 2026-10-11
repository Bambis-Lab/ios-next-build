#!/usr/bin/env python3
"""Hard wall-clock watchdog for Xcode/simulator subprocess groups on macOS."""
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
    start = time.monotonic()
    print(f"WATCHDOG_START timeout={args.timeout_seconds}s command={command[0]}", flush=True)
    process = subprocess.Popen(command, start_new_session=True)
    try:
        code = process.wait(timeout=args.timeout_seconds)
    except subprocess.TimeoutExpired:
        print(f"WATCHDOG_TIMEOUT elapsed={time.monotonic()-start:.1f}s", flush=True)
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        return 124
    elapsed = time.monotonic() - start
    print(f"WATCHDOG_EXIT code={code} elapsed={elapsed:.1f}s", flush=True)
    return code if code >= 0 else 128 - code


if __name__ == "__main__":
    sys.exit(main())
