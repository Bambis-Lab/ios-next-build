import base64
import hashlib
import json
import os
from pathlib import Path
import stat
import tempfile
import time
import unittest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from distributed_audio_relay import RelayContract,load_config
from distributed_role_provisioning import generate,write_private_bundle

class ProvisioningTests(unittest.TestCase):
    def test_all_durations_bind_role_keys_and_grants(self):
        now=int(time.time())
        for duration in (30,120,300):
            relay,clients=generate("123:1",duration,"https://fixture.invalid/",now=now)
            c=RelayContract(relay,wall=lambda:now)
            for role,peer in (("A","B"),("B","A")):
                item=clients[role]
                self.assertEqual(item["callID"],relay["call_id"])
                self.assertEqual(item["duration"],duration)
                key=Ed25519PrivateKey.from_private_bytes(base64.b64decode(item["signingSeed"]))
                encoded=base64.b64encode(key.public_key().public_bytes_raw()).decode("ascii")
                self.assertTrue(encoded==relay["roles"][role]["signing_public_key"])
                self.assertTrue(item["peerSigningKey"]==relay["roles"][peer]["signing_public_key"])
                self.assertTrue(item["signingSeed"]!=clients[peer]["signingSeed"])
                self.assertTrue(set(item["tokens"]).isdisjoint(clients[peer]["tokens"]))
                for token in item["tokens"]:
                    self.assertEqual(c.authenticate(token).device_id,"ios-"+role.lower())
                    self.assertFalse(token in json.dumps(relay))
                    self.assertFalse(token in json.dumps(clients[peer]))
                self.assertFalse(item["signingSeed"] in json.dumps(relay))
                self.assertFalse(item["signingSeed"] in json.dumps(clients[peer]))
            another,_=generate("123:1",duration,"https://fixture.invalid/",now=now)
            self.assertTrue(another["call_id"]!=relay["call_id"])

    def test_private_files_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as root:
            path=Path(root)/"private"
            relay,clients=generate("123:1",30,"https://fixture.invalid/")
            write_private_bundle(path,relay,clients)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode),0o700)
            for child in path.iterdir():
                self.assertEqual(stat.S_IMODE(child.stat().st_mode),0o600)
            self.assertTrue(load_config(path/"relay.json")==relay)
            with self.assertRaises(FileExistsError):
                write_private_bundle(path,relay,clients)
            self.assertTrue(load_config(path/"relay.json")==relay)

    def test_invalid_origin_and_duration(self):
        for origin in ("http://fixture.invalid/","https://user@fixture.invalid/","https://fixture.invalid/?x=1","https://fixture.invalid/a","https://fixture.invalid/#","https://fixture.invalid:65536/"):
            with self.assertRaises(ValueError): generate("123:1",30,origin)
        for duration in (True,600,1800):
            with self.assertRaises(ValueError): generate("123:1",duration,"https://fixture.invalid/")

if __name__=="__main__":
    unittest.main()
