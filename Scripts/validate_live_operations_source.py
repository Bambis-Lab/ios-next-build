#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def require(path: str, *needles: str) -> str:
    text = (ROOT / path).read_text(encoding="utf-8")
    missing = [needle for needle in needles if needle not in text]
    if missing:
        raise SystemExit(f"{path}: missing required contract(s): {missing}")
    return text


def forbid(path: str, *needles: str) -> None:
    text = (ROOT / path).read_text(encoding="utf-8")
    present = [needle for needle in needles if needle in text]
    if present:
        raise SystemExit(f"{path}: forbidden Live Operations coupling found: {present}")


def main() -> None:
    require(
        "Sources/Core/LiveOperationsClient.swift",
        'appending(path: "v1/live")',
        '"last_mcp_seq"',
        '"last_sentinelx_seq"',
        'Bearer ',
        'configuration.token',
        'bufferingNewest(512)',
        'Task.sleep(for: .seconds(10))',
    )
    require(
        "Sources/Core/LiveOperationsModels.swift",
        'case mcp',
        'case sentinelX = "sentinelx"',
        'case "source.snapshot"',
        'case "resync.required"',
        'online = true',
        'recentOperations.count > 50',
    )
    require(
        "Sources/Features/LiveOperationsView.swift",
        'navigationTitle("Live Operations")',
        '"MCP"',
        '"Windows PC · SentinelX"',
        'TimelineView(.periodic(from: .now, by: 1))',
        '"Read-only Telemetrie"',
    )
    require(
        "Sources/Features/SystemView.swift",
        'LiveOperationsView()',
        'Label("Live Operations"',
    )
    require(
        "Backend/live_operations/protocol.py",
        '"argument"',
        '"output"',
        '"prompt"',
        '"token"',
        '"authorization"',
        '"stdout"',
        '"stderr"',
    )
    require(
        "Backend/live_operations/server.py",
        '"/v1/live"',
        '"/v1/ingest"',
        '"last_mcp_seq"',
        '"last_sentinelx_seq"',
        'IOSNEXT_LIVE_OPERATIONS_INGEST_TOKEN',
        'read token and ingest token must be different',
        'Authorization',
        '64 * 1024',
    )
    require(
        "Backend/live_operations/ingest.py",
        'INGEST_EVENT_TYPES',
        'operation.started',
        'metrics.updated',
        '_exact_dict(message',
        '"ingest message"',
    )
    forbid(
        "Sources/Features/LiveOperationsView.swift",
        "Code Commander",
        "Remote Desktop Commander",
        "CommanderLive",
        "RemoteDesktopCommander",
    )
    forbid(
        "Sources/Core/LiveOperationsClient.swift",
        "CommanderLive",
        "RemoteDesktopCommander",
    )
    print("Live Operations portable source contract passed.")


if __name__ == "__main__":
    main()
