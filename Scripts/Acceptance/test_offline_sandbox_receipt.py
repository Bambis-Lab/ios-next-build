import base64
import json
from pathlib import Path
import tempfile
import unittest
import uuid
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from offline_sandbox_receipt import POLICY, ROLE_FILE, message, verify_receipt, cleanup_role_copies

class ReceiptTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.a, self.b, self.c = [self.root / str(uuid.uuid4()) for _ in range(3)]
        self.key = Ed25519PrivateKey.generate()
        self.item = {"callID": "a"*32, "role": "A", "baseURL": "https://fixture.invalid/", "duration": 30,
                     "signingSeed": base64.b64encode(self.key.private_bytes_raw()).decode()}
        self.raw = json.dumps(self.item).encode()
    def receipt(self, path, raw=None, key=None):
        raw = self.raw if raw is None else raw
        signature = (key or self.key).sign(message(json.loads(raw), raw, path.name))
        return "SR22_NATIVE_RECEIPT container="+path.name+" signature="+base64.b64encode(signature).decode()+"\n"
    def write(self, container, data=None):
        p = container / 'Library' / 'Application Support' / ROLE_FILE
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(self.raw if data is None else data)
        p.chmod(0o600)
        return p
    def test_unchanged(self):
        self.assertEqual(verify_receipt(self.receipt(self.a),self.raw,self.a,self.a,'')['sandbox_lifecycle'],'UNCHANGED')
    def test_explicit_offline_rotation(self):
        for p in (self.a,self.b):
            self.assertEqual(verify_receipt(self.receipt(p),self.raw,self.a,self.b,POLICY)['sandbox_lifecycle'],'VERIFIED_OFFLINE_ROTATION')
    def test_unapproved_rotation(self):
        with self.assertRaises(ValueError): verify_receipt(self.receipt(self.a),self.raw,self.a,self.b,'')
    def test_third_container(self):
        with self.assertRaises(ValueError): verify_receipt(self.receipt(self.c),self.raw,self.a,self.b,POLICY)
    def test_other_root(self):
        with self.assertRaises(ValueError): verify_receipt(self.receipt(self.a),self.raw,self.a,self.b/'nested',POLICY)
    def test_wrong_key(self):
        with self.assertRaises(ValueError): verify_receipt(self.receipt(self.a,key=Ed25519PrivateKey.generate()),self.raw,self.a,self.a,POLICY)
    def test_changed_bytes(self):
        with self.assertRaises(ValueError): verify_receipt(self.receipt(self.a),self.raw+b' ',self.a,self.a,POLICY)
    def test_missing_or_duplicate(self):
        for log in ('',self.receipt(self.a)*2):
            with self.assertRaises(ValueError): verify_receipt(log,self.raw,self.a,self.a,POLICY)
    def test_not_a_live_policy(self):
        other=json.dumps({**self.item,'baseURL':'https://other.invalid/'}).encode()
        with self.assertRaises(ValueError): verify_receipt(self.receipt(self.a,raw=other),other,self.a,self.a,POLICY)
    def test_remove_both_exact_copies(self):
        a,b=self.write(self.a),self.write(self.b)
        self.assertEqual(cleanup_role_copies(self.a,self.b,self.raw),2)
        self.assertFalse(a.exists() or b.exists())
    def test_missing_old_container(self):
        p=self.write(self.b)
        self.assertEqual(cleanup_role_copies(self.a,self.b,self.raw),1)
        self.assertFalse(p.exists())
    def test_foreign_bytes_preserved(self):
        a,b=self.write(self.a),self.write(self.b,b'foreign')
        with self.assertRaises(ValueError): cleanup_role_copies(self.a,self.b,self.raw)
        self.assertFalse(a.exists()); self.assertEqual(b.read_bytes(),b'foreign')
    def test_unexpected_third_copy_fails_and_cleans(self):
        p=self.write(self.c)
        with self.assertRaises(ValueError): cleanup_role_copies(self.a,self.b,self.raw)
        self.assertFalse(p.exists())
    def test_symlink_not_followed(self):
        p=self.write(self.a); q=self.root/'unrelated'; q.write_bytes(self.raw)
        p.unlink(); p.symlink_to(q)
        with self.assertRaises(ValueError): cleanup_role_copies(self.a,self.a,self.raw)
        self.assertEqual(q.read_bytes(),self.raw); self.assertTrue(p.is_symlink())

if __name__ == '__main__': unittest.main(verbosity=2)
