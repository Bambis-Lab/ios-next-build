"""Offline tests for the 1.7.3 public Factory OAuth metadata probe.

These tests never contact Factory or attempt OAuth registration.
"""
import importlib.util
import socket
import ssl
from urllib.error import HTTPError, URLError
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "probe_factory_oauth_metadata.py"
spec = importlib.util.spec_from_file_location("factory_probe", SCRIPT)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class FactoryOAuthMetadataProbeTests(unittest.TestCase):
    def test_matching_https_registration_and_token_urls_accepted(self):
        self.assertTrue(probe.safe_endpoint(probe.BASE + "/register"))
        self.assertTrue(probe.safe_endpoint(probe.BASE + "/oauth/token"))

    def test_cross_origin_or_insecure_dcr_endpoint_rejected(self):
        for url in (
            "http://master-appliance-build.tailff745a.ts.net/register",
            "https://different.example/register",
            "https://master-appliance-build.tailff745a.ts.net.evil.invalid/register",
            "https://user:secret@master-appliance-build.tailff745a.ts.net/register",
            probe.BASE + "/register?leak=token",
            probe.BASE + "/register#fragment",
            "",
        ):
            self.assertFalse(probe.safe_endpoint(url), url)

    def test_network_failure_categories_never_include_raw_network_or_secret_text(self):
        failures = [
            (URLError(socket.gaierror(-3, "sensitive host text")), "DNS_FAILED"),
            (URLError(TimeoutError("sensitive token value")), "TIMEOUT"),
            (URLError(ConnectionRefusedError("private host")), "CONNECTION_REFUSED"),
            (URLError(ssl.SSLError("sensitive cert contents")), "TLS_FAILED"),
            (URLError("proxy URL includes token=secret"), "NETWORK_ERROR"),
            (HTTPError(probe.BASE, 403, "sensitive body", {}, None), "HTTP_403"),
        ]
        for error, expected in failures:
            with self.subTest(expected=expected):
                self.assertEqual(probe.error_kind(error), expected)

    def test_all_http_redirects_are_declined(self):
        handler = probe.RejectRedirects()
        self.assertIsNone(handler.redirect_request(
            None, None, 307, "Temporary Redirect",
            {"Location": "https://untrusted.example"}, "https://untrusted.example"
        ))


if __name__ == "__main__":
    unittest.main()
