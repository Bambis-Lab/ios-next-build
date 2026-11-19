import base64
import copy
import hashlib
import json
import os
import secrets
import time
import unittest
from unittest.mock import patch
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from websockets.sync.client import connect
from websockets.exceptions import ConnectionClosed
from distributed_audio_relay import RelayContract
from audio_fixture.audio_websocket import ManagedAudioListener

class ContractTests(unittest.TestCase):
    def setUp(self):
        self.now=int(time.time())
        self.wall=self.now
        self.steady=0
        self.tokens={role:[secrets.token_hex(32) for _ in range(3)] for role in ("A","B")}
        self.config={"version":1,"run":"123:1","call_id":secrets.token_hex(16),"duration":30,
            "expires_at":self.now+300,"roles":{}}
        for role,tokens in self.tokens.items():
            self.config["roles"][role]={"signing_public_key":base64.b64encode(
                Ed25519PrivateKey.generate().public_key().public_bytes_raw()).decode("ascii"),
                "grants":[{"sha256":hashlib.sha256(t.encode("ascii")).hexdigest(),"expires_at":self.now+60*(i+1)}
                          for i,t in enumerate(tokens)]}
    def contract(self):
        return RelayContract(self.config,wall=lambda:self.wall,steady=lambda:self.steady)
    def test_role_and_expiry(self):
        c=self.contract()
        self.assertEqual(c.authenticate(self.tokens["A"][0]).device_id,"ios-a")
        self.assertEqual(c.authenticate(self.tokens["B"][0]).device_id,"ios-b")
        self.assertIsNone(c.authenticate(secrets.token_hex(32)))
        self.steady=61
        self.wall-=1000
        self.assertIsNone(c.authenticate(self.tokens["A"][0]))
        self.assertIsNotNone(c.authenticate(self.tokens["A"][1]))
        self.steady=301
        self.assertFalse(c.active("ha-fixture-a","ios-a"))
    def test_reject_duplicate_and_old_duration(self):
        original=copy.deepcopy(self.config)
        self.config["roles"]["B"]["grants"][0]["sha256"]=self.config["roles"]["A"]["grants"][0]["sha256"]
        with self.assertRaises(ValueError): self.contract()
        self.config=copy.deepcopy(original)
        self.config["roles"]["B"]["signing_public_key"]=self.config["roles"]["A"]["signing_public_key"]
        with self.assertRaises(ValueError): self.contract()
        self.config=copy.deepcopy(original)
        self.config["duration"]=600
        with self.assertRaises(ValueError): self.contract()
    def test_real_loopback_auth_and_cross_role_refresh(self):
        c=self.contract()
        with patch.dict(os.environ,{"IOSNEXT_EXPERIMENTAL_AUDIO":"true"}):
            listener=ManagedAudioListener(c.broker(),0)
            try:
                url="ws://127.0.0.1:%d/v1/audio"%listener.port
                def bind(token):
                    ws=connect(url,additional_headers={"Authorization":"Bearer "+token},open_timeout=3,close_timeout=1)
                    ws.send(json.dumps({"call_id":c.call_id}))
                    return ws
                with bind(self.tokens["A"][0]) as a,bind(self.tokens["B"][0]) as b:
                    self.assertTrue(json.loads(a.recv(timeout=3))["bound"])
                    self.assertTrue(json.loads(b.recv(timeout=3))["bound"])
                    a.send(json.dumps({"action":"refresh","token":self.tokens["A"][1]}))
                    self.assertEqual(json.loads(a.recv(timeout=3))["result"]["expires_at"],self.now+120)
                    a.send(json.dumps({"action":"refresh","token":self.tokens["B"][2]}))
                    with self.assertRaises(ConnectionClosed): a.recv(timeout=3)
                with bind(secrets.token_hex(32)) as stranger:
                    with self.assertRaises(ConnectionClosed): stranger.recv(timeout=3)
            finally:
                listener.close()

if __name__=="__main__":
    unittest.main()
