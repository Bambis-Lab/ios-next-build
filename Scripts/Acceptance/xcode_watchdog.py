#!/usr/bin/env python3
"""Compatibility command wrapper that deliberately imposes no timeout.

The historical --timeout-seconds argument is accepted and ignored so existing
local invocations keep working, but child commands are never terminated due to
elapsed wall-clock time. GitHub-hosted runners may still enforce platform limits.
"""
import subprocess
import sys


def main():
    args = sys.argv[1:]
    if args and args[0] == "--timeout-seconds":
        if len(args) < 2:
            raise SystemExit("Expected a value after --timeout-seconds")
        args = args[2:]
    if args and args[0] == "--":
        args = args[1:]
    if not args:
        raise SystemExit("Usage: xcode_watchdog.py [--timeout-seconds IGNORED] -- command [args...]")
    print(f"XCODE_NO_TIMEOUT command={args[0]}", flush=True)
    try:
        return subprocess.run(args, check=False).returncode
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
