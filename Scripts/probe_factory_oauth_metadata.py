#!/usr/bin/env python3
"""Unauthenticated *observation* of the actual Factory OAuth metadata.

This never requests tokens, launches an authorization session, writes to a
backend or treats reachability as proof that an iPhone user has logged in.
"""
import json
import socket
import ssl
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

BASE = "https://master-appliance-build.tailff745a.ts.net"
RESOURCE = BASE + "/mcp"


class RejectRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


OPENER = build_opener(RejectRedirects())


def safe_endpoint(value):
    """Read-only issuer-relative URL verification without leaking endpoint paths."""
    try:
        url = urlsplit(value)
        origin = urlsplit(BASE)
        return (url.scheme == "https" and url.hostname == origin.hostname and
                url.port == origin.port and not url.username and not url.password and
                not url.fragment and not url.query and bool(url.path))
    except (ValueError, TypeError, AttributeError):
        return False


def error_kind(error):
    """A fixed-category, non-sensitive network failure classification."""
    if isinstance(error, HTTPError):
        return f"HTTP_{error.code}"
    reason = error.reason if isinstance(error, URLError) else error
    if isinstance(reason, ssl.SSLCertVerificationError):
        return "TLS_VERIFY_FAILED"
    if isinstance(reason, ssl.SSLError):
        return "TLS_FAILED"
    if isinstance(reason, socket.gaierror):
        return "DNS_FAILED"
    if isinstance(reason, (TimeoutError, socket.timeout)):
        return "TIMEOUT"
    if isinstance(reason, ConnectionRefusedError):
        return "CONNECTION_REFUSED"
    return "NETWORK_ERROR"


def dns_status():
    """Only report resolution success, never the resolved network addresses."""
    try:
        return "RESOLVED" if socket.getaddrinfo(urlsplit(BASE).hostname, 443) else "NO_RECORDS"
    except (OSError, ValueError, TypeError):
        return "FAILED"


def fetch(url):
    req = Request(url, headers={"Accept": "application/json"})
    with OPENER.open(req, timeout=7) as reply:
        raw = reply.read(50_000)
        if len(raw) >= 50_000:
            raise ValueError("OAuth metadata response too large")
        return json.loads(raw)


def main():
    print(f"GATEWAY_DNS={dns_status()}")
    protected = None
    for path in ["/.well-known/oauth-protected-resource/mcp",
                 "/.well-known/oauth-protected-resource"]:
        try:
            value = fetch(BASE + path)
            if value.get("resource") == RESOURCE:
                protected = value
                break
        except (HTTPError, URLError, TimeoutError, ValueError, OSError) as ex:
            print(f"GATEWAY_PROBE_PATH={path} result={error_kind(ex)}")
    if protected is None:
        print("GATEWAY_METADATA=NOT_VERIFIED runner_network_or_metadata_unavailable")
        return

    servers = protected.get("authorization_servers", [])
    if BASE not in servers:
        print("GATEWAY_METADATA=INCOMPATIBLE authorization_server_mismatch")
        return
    try:
        auth = fetch(BASE + "/.well-known/oauth-authorization-server")
    except (HTTPError, URLError, TimeoutError, ValueError, OSError) as ex:
        print(f"GATEWAY_METADATA=NOT_VERIFIED auth_metadata_{error_kind(ex)}")
        return
    if auth.get("issuer") != BASE:
        print("GATEWAY_METADATA=INCOMPATIBLE issuer_mismatch")
    elif "S256" not in auth.get("code_challenge_methods_supported", []):
        print("GATEWAY_METADATA=INCOMPATIBLE pkce_s256_missing")
    elif not auth.get("registration_endpoint"):
        print("GATEWAY_METADATA=INCOMPATIBLE dynamic_registration_missing")
    elif not all(safe_endpoint(auth.get(key)) for key in (
        "authorization_endpoint", "token_endpoint", "registration_endpoint"
    )):
        print("GATEWAY_METADATA=INCOMPATIBLE oauth_endpoint_origin_or_scheme")
    else:
        print("GATEWAY_METADATA=PUBLIC_CONTRACT_VERIFIED")
        # HEAD has safe HTTP semantics and does not create or register a client.
        # 200/204/405/501 are observations, not proof that the DCR POST works.
        try:
            head = Request(auth["registration_endpoint"], method="HEAD")
            with OPENER.open(head, timeout=7) as reply:
                code = reply.status
        except HTTPError as error:
            code = error.code
        except (URLError, TimeoutError, OSError, ValueError):
            code = None
        print(f"GATEWAY_DCR_HEAD_STATUS={code if code is not None else 'UNREACHABLE'}")
        print("GATEWAY_DCR_POST=NOT_TESTED")
        print("GATEWAY_USER_OAUTH_SESSION=NOT_TESTED")
        print("GATEWAY_AUTHENTICATED_MCP=NOT_TESTED")


if __name__ == "__main__":
    main()
