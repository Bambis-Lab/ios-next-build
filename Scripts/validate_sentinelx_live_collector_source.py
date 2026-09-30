#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "Scripts/SentinelX/live_operations_collector.ps1"


def main() -> None:
    text = PATH.read_text(encoding="utf-8")
    required = (
        "IOSNEXT_LIVE_OPERATIONS_INGEST_URL",
        "IOSNEXT_LIVE_OPERATIONS_INGEST_TOKEN",
        "ClientWebSocket",
        "Win32_ProcessStartTrace",
        "Win32_ProcessStopTrace",
        "Get-CimInstance Win32_OperatingSystem",
        "Get-CimInstance Win32_Processor",
        "Get-CimInstance Win32_LogicalDisk",
        "cpu_percent",
        "memory_percent",
        "disk_percent",
        "source = 'sentinelx'",
        "operation.started",
        "operation.completed",
        "MetricIntervalSeconds = 2",
        "DiskIntervalSeconds = 10",
    )
    missing = [item for item in required if item not in text]
    if missing:
        raise SystemExit(f"SentinelX collector missing required contracts: {missing}")

    forbidden = (
        "CommandLine",
        "Get-Content",
        "stdout",
        "stderr",
        "prompt",
        "arguments =",
        "password",
        "private_key",
    )
    present = [item for item in forbidden if item.lower() in text.lower()]
    if present:
        raise SystemExit(f"SentinelX collector contains forbidden telemetry surface: {present}")

    if text.count("IOSNEXT_LIVE_OPERATIONS_INGEST_TOKEN") < 2:
        raise SystemExit("SentinelX collector must source the ingest token only from environment/configuration flow")

    print("SentinelX Windows live collector source contract passed.")


if __name__ == "__main__":
    main()
