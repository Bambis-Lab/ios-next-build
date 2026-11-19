import base64
import json
import os
from pathlib import Path
import tempfile
import unittest
from native_role_handoff import read_private, validate, install_role, relay_fingerprint
from run_distributed_native_role import extract

class HandoffTests(unittest.TestCase):
    def setUp(self):
        key=base64.b64encode(b"x"*32).decode()
        self.item={"version":1,"role":"A","duration":30,"callID":"a"*32,
                   "baseURL":"https://fixture.invalid/","expiresAt":1500,
                   "signingSeed":key,"peerSigningKey":key,"peerAgreementKey":key,
                   "tokens":["1"*64,"2"*64,"3"*64],"grantExpiries":[1100,1200,1500]}
    def raw(self,**changes): return json.dumps({**self.item,**changes}).encode()
    def test_private_file_and_exclusive_container_copy(self):
        with tempfile.TemporaryDirectory() as root:
            source=Path(root)/"role"
            fd=os.open(source,os.O_CREAT|os.O_WRONLY|os.O_EXCL,0o600)
            with os.fdopen(fd,"wb") as f: f.write(self.raw())
            raw=read_private(source)
            container=Path(root)/"test-container"; container.mkdir()
            target=install_role(raw,container,"A",30,now=1000)
            self.assertEqual(target.read_bytes(),raw)
            self.assertEqual(target.stat().st_mode&0o777,0o600)
            with self.assertRaises(FileExistsError): install_role(raw,container,"A",30,now=1000)
            self.assertEqual(target.read_bytes(),raw)
            source.chmod(0o644)
            with self.assertRaises(ValueError): read_private(source)
            alias=Path(root)/"alias"; alias.symlink_to(source)
            with self.assertRaises(OSError): read_private(alias)
    def test_wrong_role_expiry_origin_and_reused_tokens(self):
        for changes in ({"role":"B"},{"duration":120},{"expiresAt":1029},
                        {"baseURL":"http://fixture.invalid"},{"tokens":["1"*64]*3},
                        {"baseURL":"https://user@fixture.invalid/"}):
            with self.assertRaises(ValueError): validate(self.raw(**changes),"A",30,now=1000)
    def test_reject_symlink_container_subdirectory(self):
        with tempfile.TemporaryDirectory() as root:
            container=Path(root)/"container"; container.mkdir()
            outside=Path(root)/"outside"; outside.mkdir()
            (container/"Library").symlink_to(outside,target_is_directory=True)
            with self.assertRaises(ValueError): install_role(self.raw(),container,"A",30,now=1000)
            self.assertEqual(list(outside.iterdir()),[])
    def test_native_marker_requires_real_pass_exact_count_and_relay_binding(self):
        uid="11111111-1111-1111-1111-111111111111"
        relay=relay_fingerprint(self.item)
        marker=f"V64_NATIVE_MEDIA role=A sent=1500 received=1500 renewals=2 elapsed=30.1 started=1000.0 finished=1030.1 relay={relay}"
        process=f"IOS173_DUAL_RESULT role=A udid={uid} pid=77 sent=1500 received=1500 elapsed=30"
        log="** TEST EXECUTE SUCCEEDED **\nExecuted 1 test, with 0 failures\n"+marker+"\n"+process
        self.assertEqual(extract(log,uid,"A",30,uid,relay)["sent"],1500)
        for bad in (log.replace("1500","1499",1),log.replace("SUCCEEDED","FAILED"),log+"\n"+marker):
            with self.assertRaises(ValueError): extract(bad,uid,"A",30,uid,relay)
        with self.assertRaises(ValueError): extract(log,uid,"A",30,uid,"b"*64)
        with self.assertRaises(ValueError): extract(log,"wrong","A",30,uid,relay)
if __name__=="__main__": unittest.main()
