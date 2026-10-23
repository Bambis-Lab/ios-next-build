"""Render-only FIX-07 staging *sealed* ingress, not the family broker.

Intentionally contains NO import, connection or startup path to Home Assistant,
Factory, Owner/Family backend, database or credentials. The public Render
HTTPS URL is only a quarantined connectivity placeholder until the separate
staging HA/broker environment is independently reviewed and deployed.
"""
from __future__ import annotations

import json
import os
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SAFE_STATUS = {
    "service": "iosnext-family-stage",
    "mode": "sealed",
    "ha_connected": False,
    "family_auth_enabled": False,
    "owner_enabled": False,
    "real_e2e": False,
    "release_ready": False,
}

class SealedStageHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, status: HTTPStatus, message: dict | None = None, *, head: bool = False) -> None:
        body = json.dumps(message or {}, separators=(",", ":"), sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store, max-age=0")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("X-Robots-Tag", "noindex, nofollow")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
        self.end_headers()
        if not head:
            self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path in ("/", "/healthz", "/__stage__/status"):
            self._send(HTTPStatus.OK, SAFE_STATUS)
        else:
            self.close_connection = True
            self._send(HTTPStatus.SERVICE_UNAVAILABLE, {"error": "stage_sealed"})

    def do_HEAD(self) -> None:
        if self.path in ("/", "/healthz", "/__stage__/status"):
            self._send(HTTPStatus.OK, SAFE_STATUS, head=True)
        else:
            self.close_connection = True
            self._send(HTTPStatus.SERVICE_UNAVAILABLE, {"error": "stage_sealed"}, head=True)

    def do_POST(self) -> None:
        self.close_connection = True
        self._send(HTTPStatus.SERVICE_UNAVAILABLE, {"error": "stage_sealed"})

    def do_PUT(self) -> None:
        self.close_connection = True
        self._send(HTTPStatus.SERVICE_UNAVAILABLE, {"error": "stage_sealed"})

    def do_PATCH(self) -> None:
        self.close_connection = True
        self._send(HTTPStatus.SERVICE_UNAVAILABLE, {"error": "stage_sealed"})

    def do_DELETE(self) -> None:
        self.close_connection = True
        self._send(HTTPStatus.SERVICE_UNAVAILABLE, {"error": "stage_sealed"})

    def do_OPTIONS(self) -> None:
        self.close_connection = True
        self._send(HTTPStatus.SERVICE_UNAVAILABLE, {"error": "stage_sealed"})

    def log_message(self, format: str, *args: object) -> None:
        # Do not print paths or supplied headers even for malformed requests.
        pass


def main() -> None:
    if (os.environ.get("IOSNEXT_STAGE_SEALED") != "true"
            or os.environ.get("IOSNEXT_STAGE_DEPLOYMENT") != "render-synthetic-sealed"):
        raise SystemExit("stage_mode_not_authorized")
    try:
        port = int(os.environ.get("PORT", "10000"))
    except ValueError as exc:
        raise SystemExit("stage_port_invalid") from exc
    if not 1 <= port <= 65535:
        raise SystemExit("stage_port_invalid")
    with ThreadingHTTPServer(("0.0.0.0", port), SealedStageHandler) as server:
        print("FAM_STAGE_RENDER=SEALED real_e2e=false no_ha_access=true", flush=True)
        server.serve_forever(poll_interval=0.5)


if __name__ == "__main__":
    main()
