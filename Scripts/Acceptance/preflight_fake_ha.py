#!/usr/bin/env python3
"""Strict local Home Assistant WebSocket handshake readiness (no test shortcuts).

Unlike a bare TCP connect, require the exact fake-HA WebSocket upgrade and an
auth_required message. The fixture must remain live. Never contact real HA.
"""
from __future__ import annotations
import argparse
import base64
import json
import os
import socket
import struct
import time

def read_exact(sock: socket.socket, length: int) -> bytes:
    out = bytearray()
    while len(out) < length:
        piece = sock.recv(length - len(out))
        if not piece:
            raise OSError("fake HA socket closed before payload")
        out.extend(piece)
    return bytes(out)

def check(host: str, port: int) -> None:
    with socket.create_connection((host, port), timeout=1.5) as sock:
        sock.settimeout(1.5)
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        sock.sendall((
            "GET /api/websocket?mode=normal HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        ).encode("ascii"))
        data = bytearray()
        while b"\r\n\r\n" not in data:
            chunk = sock.recv(4096)
            if not chunk:
                raise OSError("fake HA upgrade not returned")
            data.extend(chunk)
            if len(data) > 16384:
                raise ValueError("unexpectedly long WebSocket upgrade")
        header, remaining = bytes(data).split(b"\r\n\r\n", 1)
        if not header.startswith(b"HTTP/1.1 101 Switching Protocols"):
            raise ValueError("unexpected WebSocket status")
        from hashlib import sha1
        expected = base64.b64encode(sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        if f"sec-websocket-accept: {expected}".lower().encode("ascii") not in header.lower():
            raise ValueError("WebSocket accept key mismatch")
        buffer = bytearray(remaining)
        def take(n: int) -> bytes:
            while len(buffer) < n:
                block = sock.recv(4096)
                if not block:
                    raise OSError("missing fake HA welcome frame")
                buffer.extend(block)
            v = bytes(buffer[:n])
            del buffer[:n]
            return v
        first, second = take(2)
        if first & 0x0f != 1 or second & 0x80:
            raise ValueError("expected unmasked text greeting")
        length = second & 0x7f
        if length == 126:
            length = struct.unpack("!H", take(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", take(8))[0]
        if length > 4096:
            raise ValueError("greeting too long")
        obj = json.loads(take(length))
        if obj.get("type") != "auth_required" or obj.get("ha_version") != "2026.9.0":
            raise ValueError("wrong fake HA server greeting")

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18765)
    parser.add_argument("--attempts", type=int, default=60)
    args = parser.parse_args()
    for attempt in range(1, args.attempts + 1):
        try:
            check(args.host, args.port)
            # Confirm repeated availability instead of accepting one lucky TCP.
            time.sleep(0.25)
            check(args.host, args.port)
        except (OSError, TimeoutError, ValueError, json.JSONDecodeError) as e:
            if attempt == args.attempts:
                print(f"FAM_FAKE_HA_WEBSOCKET_READY=FAIL reason={type(e).__name__}", flush=True)
                return 65
            time.sleep(0.5)
        else:
            print(f"FAM_FAKE_HA_WEBSOCKET_READY=PASS attempt={attempt}", flush=True)
            return 0
    return 65

if __name__ == "__main__":
    raise SystemExit(main())
