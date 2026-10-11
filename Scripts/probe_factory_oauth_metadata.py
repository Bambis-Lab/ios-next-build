#!/usr/bin/env python3
"""Unauthenticated *observation* of the actual Factory OAuth metadata.

This never requests tokens, launches an authorization session, writes to a
backend or treats reachability as proof that an iPhone user has logged in.
"""
import json
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

BASE = "https://master-appliance-build.tailff745a.ts.net"
RESOURCE = BASE + "/mcp"


def fetch(url):
    req = Request(url, headers={"Accept": "application/json"})
    with urlopen(req, timeout=7) as reply:
        raw = reply.read(50_000)
        if len(raw) >= 50_000:
            raise ValueError("OAuth metadata response too large")
        return json.loads(raw)


def main():
    protected = None
    for path in ["/.well-known/oauth-protected-resource/mcp",
                 "/.well-known/oauth-protected-resource"]:
        try:
            value = fetch(BASE + path)
            if value.get("resource") == RESOURCE:
                protected = value
                break
        except (HTTPError, URLError, TimeoutError, ValueError, OSError) as ex:
            print(f"GATEWAY_PROBE_PATH={path} result={type(ex).__name__}")
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
        print(f"GATEWAY_METADATA=NOT_VERIFIED auth_metadata_{type(ex).__name__}")
        return
    if auth.get("issuer") != BASE:
        print("GATEWAY_METADATA=INCOMPATIBLE issuer_mismatch")
    elif "S256" not in auth.get("code_challenge_methods_supported", []):
        print("GATEWAY_METADATA=INCOMPATIBLE pkce_s256_missing")
    elif not auth.get("registration_endpoint"):
        print("GATEWAY_METADATA=INCOMPATIBLE dynamic_registration_missing")
    else:
        print("GATEWAY_METADATA=PUBLIC_CONTRACT_VERIFIED")
        print("GATEWAY_USER_OAUTH_SESSION=NOT_TESTED")
        print("GATEWAY_AUTHENTICATED_MCP=NOT_TESTED")


if __name__ == "__main__":
    main()
