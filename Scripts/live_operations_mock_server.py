#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
from datetime import datetime, timezone
from urllib.parse import parse_qs, urlparse

from websockets.asyncio.server import ServerConnection, serve


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def envelope(source: str, seq: int, event_type: str, payload: dict) -> str:
    return json.dumps({
        "schema": 1,
        "source": source,
        "seq": seq,
        "type": event_type,
        "timestamp": now(),
        "payload": payload,
    }, separators=(",", ":"))


def snapshot(source: str, seq: int) -> str:
    if source == "mcp":
        value = {
            "source": "mcp",
            "online": True,
            "last_seq": seq,
            "active_operations": [],
            "recent_operations": [],
            "metrics": {},
            "source_metadata": {"relay": "mock"},
        }
    else:
        value = {
            "source": "sentinelx",
            "online": True,
            "last_seq": seq,
            "active_operations": [],
            "recent_operations": [],
            "metrics": {"cpu_percent": 22.5, "memory_percent": 61.7, "disk_percent": 47.0},
            "source_metadata": {"host": "DESKTOP-J94UIA0", "agent_version": "0.18.4"},
        }
    return envelope(source, seq, "source.snapshot", {"snapshot": value})


async def handler(connection: ServerConnection) -> None:
    query = parse_qs(urlparse(connection.request.path).query)
    mcp_seq = int(query.get("last_mcp_seq", ["0"])[0])
    sx_seq = int(query.get("last_sentinelx_seq", ["0"])[0])

    if mcp_seq == 0:
        mcp_seq = 1
        await connection.send(snapshot("mcp", mcp_seq))
    if sx_seq == 0:
        sx_seq = 1
        await connection.send(snapshot("sentinelx", sx_seq))

    await asyncio.sleep(0.25)
    mcp_seq += 1
    operation = {
        "id": "mcp_mock_1",
        "source": "mcp",
        "kind": "toolCall",
        "title": "GitHub.fetch_file",
        "state": "running",
        "started_at": now(),
        "updated_at": now(),
        "repository": "Bambis-Lab/ios-next",
    }
    await connection.send(envelope("mcp", mcp_seq, "operation.started", {"operation": operation}))

    for cpu in (23.0, 24.0, 25.0):
        await asyncio.sleep(0.5)
        sx_seq += 1
        await connection.send(envelope("sentinelx", sx_seq, "metrics.updated", {
            "metrics": {"cpu_percent": cpu, "memory_percent": 61.7, "disk_percent": 47.0},
            "source_metadata": {"host": "DESKTOP-J94UIA0", "agent_version": "0.18.4"},
        }))

    await asyncio.sleep(0.5)
    mcp_seq += 1
    operation.update({"state": "completed", "updated_at": now(), "completed_at": now(), "duration_ms": 2250})
    await connection.send(envelope("mcp", mcp_seq, "operation.completed", {"operation": operation}))

    while True:
        await asyncio.sleep(10)
        mcp_seq += 1
        sx_seq += 1
        await connection.send(envelope("mcp", mcp_seq, "heartbeat", {}))
        await connection.send(envelope("sentinelx", sx_seq, "heartbeat", {}))


async def main() -> None:
    parser = argparse.ArgumentParser(description="Deterministic iOS Next Live Operations mock relay")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    async with serve(handler, args.host, args.port, max_size=64 * 1024):
        print(f"LIVE_OPERATIONS_MOCK=READY ws://{args.host}:{args.port}/v1/live", flush=True)
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
