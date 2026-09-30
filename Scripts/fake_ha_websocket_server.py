#!/usr/bin/env python3
import argparse
import base64
import hashlib
import json
import socket
import socketserver
import struct
import threading
import time
from urllib.parse import parse_qs, urlsplit

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
mode_counts = {}
mode_lock = threading.Lock()


def recv_exact(sock, count):
    data = bytearray()
    while len(data) < count:
        chunk = sock.recv(count - len(data))
        if not chunk:
            raise ConnectionError("socket closed")
        data.extend(chunk)
    return bytes(data)


def read_http_request(sock):
    data = bytearray()
    while b"\r\n\r\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("socket closed before handshake")
        data.extend(chunk)
        if len(data) > 65536:
            raise ValueError("handshake too large")
    return data.decode("latin1")


def read_frame(sock):
    header = recv_exact(sock, 2)
    first, second = header
    opcode = first & 0x0F
    masked = bool(second & 0x80)
    length = second & 0x7F
    if length == 126:
        length = struct.unpack("!H", recv_exact(sock, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", recv_exact(sock, 8))[0]
    if length > 8 * 1024 * 1024:
        raise ValueError("frame too large")
    mask = recv_exact(sock, 4) if masked else None
    payload = bytearray(recv_exact(sock, length))
    if mask:
        for index in range(length):
            payload[index] ^= mask[index % 4]
    return opcode, bytes(payload)


def send_frame(sock, opcode, payload=b""):
    first = 0x80 | (opcode & 0x0F)
    length = len(payload)
    if length < 126:
        header = bytes([first, length])
    elif length <= 0xFFFF:
        header = bytes([first, 126]) + struct.pack("!H", length)
    else:
        header = bytes([first, 127]) + struct.pack("!Q", length)
    sock.sendall(header + payload)


def send_json(sock, payload):
    send_frame(sock, 0x1, json.dumps(payload, separators=(",", ":")).encode("utf-8"))


def state(entity_id, value, attrs):
    return {
        "entity_id": entity_id,
        "state": value,
        "attributes": attrs,
    }


def fire_tv_state(value="playing", title="Companion Testfilm"):
    return state(
        "media_player.fire_tv_companion",
        value,
        {
            "friendly_name": "Fire TV Companion",
            "media_title": title,
            "media_content_type": "video",
            "media_position": 42,
            "media_duration": 1800,
            "volume_level": 0.52,
            "is_volume_muted": False,
            "supported_features": 21439,
            "skip_interval_seconds": 10,
            "power_state": "awake",
            "foreground_package": "com.example.video",
            "foreground_app": "Video",
            "capabilities": {
                "capability_version": 2,
                "launch_apps": True,
                "player_control": True,
                "media_session": True,
                "volume_control": True,
                "mute_control": True,
                "queue_control": True,
                "foreground_app": True,
                "global_navigation": True,
                "standby_control": True,
                "wake_control": True,
                "power_control": True,
            },
        },
    )


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        sock = self.request
        sock.settimeout(15)
        try:
            request = read_http_request(sock)
            lines = request.split("\r\n")
            request_line = lines[0].split()
            if len(request_line) < 2:
                return

            target = request_line[1]
            query = parse_qs(urlsplit(target).query)
            mode = query.get("mode", ["normal"])[0]

            headers = {}
            for line in lines[1:]:
                if ":" in line:
                    key, value = line.split(":", 1)
                    headers[key.strip().lower()] = value.strip()

            websocket_key = headers.get("sec-websocket-key")
            if not websocket_key:
                return

            accept = base64.b64encode(
                hashlib.sha1((websocket_key + GUID).encode("ascii")).digest()
            ).decode("ascii")

            sock.sendall(
                (
                    "HTTP/1.1 101 Switching Protocols\r\n"
                    "Upgrade: websocket\r\n"
                    "Connection: Upgrade\r\n"
                    f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
                ).encode("ascii")
            )

            with mode_lock:
                mode_counts[mode] = mode_counts.get(mode, 0) + 1
                connection_number = mode_counts[mode]

            print(
                f"connection mode={mode} number={connection_number}",
                flush=True,
            )

            if mode == "auth_stall":
                time.sleep(5)
                return

            send_json(sock, {"type": "auth_required", "ha_version": "2026.9.0"})

            while True:
                opcode, payload = read_frame(sock)

                if opcode == 0x8:
                    return

                if opcode == 0x9:
                    if mode != "no_pong":
                        send_frame(sock, 0xA, payload)
                    continue

                if opcode != 0x1:
                    continue

                message = json.loads(payload.decode("utf-8"))
                msg_type = message.get("type")
                msg_id = message.get("id")
                print(
                    f"message mode={mode} number={connection_number} type={msg_type} id={msg_id}",
                    flush=True,
                )

                if msg_type == "auth":
                    send_json(sock, {"type": "auth_ok", "ha_version": "2026.9.0"})

                elif msg_type == "auth/current_user":
                    send_json(
                        sock,
                        {
                            "id": msg_id,
                            "type": "result",
                            "success": True,
                            "result": {
                                "id": "11111111-1111-1111-1111-111111111111",
                                "name": "Nico",
                                "is_owner": True,
                            },
                        },
                    )

                elif msg_type == "get_states":
                    send_json(
                        sock,
                        {
                            "id": msg_id,
                            "type": "result",
                            "success": True,
                            "result": [
                                state(
                                    "light.fake",
                                    "on",
                                    {
                                        "friendly_name": "Fake Light",
                                        "brightness": 128,
                                    },
                                ),
                                fire_tv_state(
                                    title=(
                                        "Companion Initial"
                                        if mode == "close_once" and connection_number == 1
                                        else "Companion Reconnected"
                                        if mode == "close_once"
                                        else "Companion Testfilm"
                                    )
                                ),
                            ],
                        },
                    )

                elif mode == "registry_unsupported" and msg_type in {
                    "config/floor_registry/list",
                    "config/area_registry/list",
                    "config/device_registry/list",
                    "config/entity_registry/list",
                }:
                    send_json(
                        sock,
                        {
                            "id": msg_id,
                            "type": "result",
                            "success": False,
                            "error": {"message": f"Unsupported type: {msg_type}"},
                        },
                    )

                elif msg_type == "config/floor_registry/list":
                    send_json(
                        sock,
                        {
                            "id": msg_id,
                            "type": "result",
                            "success": True,
                            "result": [
                                {"floor_id": "ground_floor", "name": "Erdgeschoss", "level": 0},
                            ],
                        },
                    )

                elif msg_type == "config/area_registry/list":
                    send_json(
                        sock,
                        {
                            "id": msg_id,
                            "type": "result",
                            "success": True,
                            "result": [
                                {"area_id": "living_room", "name": "Wohnzimmer", "floor_id": "ground_floor"},
                                {"area_id": "nico_room", "name": "Nico Zimmer", "floor_id": None},
                            ],
                        },
                    )

                elif msg_type == "config/device_registry/list":
                    send_json(
                        sock,
                        {
                            "id": msg_id,
                            "type": "result",
                            "success": True,
                            "result": [
                                {"id": "device-light", "name": "Fake Light", "area_id": "living_room"},
                                {"id": "device-firetv", "name": "Fire TV Companion", "area_id": "living_room"},
                            ],
                        },
                    )

                elif msg_type == "config/entity_registry/list":
                    send_json(
                        sock,
                        {
                            "id": msg_id,
                            "type": "result",
                            "success": True,
                            "result": [
                                {"entity_id": "light.fake", "device_id": "device-light", "area_id": None, "platform": "hue"},
                                {"entity_id": "media_player.fire_tv_companion", "device_id": "device-firetv", "area_id": None, "platform": "firetv_companion"},
                            ],
                        },
                    )

                elif msg_type == "subscribe_events":
                    send_json(
                        sock,
                        {
                            "id": msg_id,
                            "type": "result",
                            "success": True,
                            "result": None,
                        },
                    )

                    should_close = mode == "close_after_subscribe" or (
                        mode == "close_once" and connection_number == 1
                    )
                    if should_close:
                        time.sleep(1.0)
                        send_frame(sock, 0x8, struct.pack("!H", 1001))
                        return

                elif msg_type == "call_service":
                    if mode == "call_stall":
                        continue

                    send_json(
                        sock,
                        {
                            "id": msg_id,
                            "type": "result",
                            "success": True,
                            "result": None,
                        },
                    )

                    target_data = message.get("target")
                    entity_id = target_data.get("entity_id") if isinstance(target_data, dict) else None
                    if (
                        entity_id == "media_player.fire_tv_companion"
                        and message.get("domain") == "media_player"
                        and message.get("service") == "media_pause"
                    ):
                        send_json(
                            sock,
                            {
                                "type": "event",
                                "event": {
                                    "event_type": "state_changed",
                                    "data": {
                                        "entity_id": "media_player.fire_tv_companion",
                                        "new_state": fire_tv_state("paused"),
                                    },
                                },
                            },
                        )

                elif msg_id is not None:
                    send_json(
                        sock,
                        {
                            "id": msg_id,
                            "type": "result",
                            "success": False,
                            "error": {"message": f"Unsupported type: {msg_type}"},
                        },
                    )

        except (ConnectionError, TimeoutError, socket.timeout, BrokenPipeError, ConnectionResetError):
            return


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18765)
    parser.add_argument("--port-file")
    args = parser.parse_args()

    with Server((args.host, args.port), Handler) as server:
        actual_port = server.server_address[1]
        if args.port_file:
            with open(args.port_file, "w", encoding="utf-8") as handle:
                handle.write(str(actual_port))
                handle.flush()
        print(f"fake-ha-listening={args.host}:{actual_port}", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
