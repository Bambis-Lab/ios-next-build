import copy
import unittest
from validate_distributed_media import validate

class NativeEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.stage={"source":"a"*40,"run":"123","attempt":"1","duration":30}
        self.a={"version":1,**self.stage,"role":"A","build_sha256":"b"*64,
            "host_boot_sha256":"c"*64,"simulator":"11111111-1111-1111-1111-111111111111",
            "xcresult_device":"11111111-1111-1111-1111-111111111111","test_name":"testDistributedA",
            "test_pass":True,"pid":77,"sent":1500,"received":1500,"elapsed_seconds":30.1,
            "media_started_utc":1000.0,"media_finished_utc":1030.1,
            "relay_session_sha256":"d"*64,"renewals":2,"physical_audio":False}
        self.b={**self.a,"role":"B","host_boot_sha256":"e"*64,"test_name":"testDistributedB",
            "media_started_utc":1000.1,"media_finished_utc":1030.2}
    def check(self,a=None,b=None):
        return validate(self.a if a is None else a,self.b if b is None else b,**self.stage)
    def test_valid_independent_hosts_may_reuse_template_udid_and_pid(self):
        result=self.check()
        self.assertEqual(result["total_frames"],3000)
        self.assertEqual(result["g03"],"REMAINING_GATES_REQUIRED")
    def test_reject_same_host_or_different_products_relay_or_source(self):
        for field,value in (("host_boot_sha256",self.a["host_boot_sha256"]),("build_sha256","f"*64),
            ("relay_session_sha256","f"*64),("source","b"*40),("attempt","2"),("run","124")):
            with self.subTest(field=field),self.assertRaises(ValueError):
                self.check(b={**self.b,field:value})
    def test_reject_non_native_or_wrong_destination_and_missing_frames(self):
        for field,value in (("test_name","testNativeExecutionPrerequisite"),("test_pass",False),
            ("xcresult_device","different"),("sent",1499),("received",1499),("renewals",1),("physical_audio",True)):
            with self.subTest(field=field),self.assertRaises(ValueError):
                self.check(b={**self.b,field:value})
    def test_reject_nonoverlapping_or_invalid_timing(self):
        for changes in ({"media_started_utc":1031,"media_finished_utc":1061.1},
            {"elapsed_seconds":float("nan")},{"elapsed_seconds":29.9},{"media_finished_utc":1100}):
            with self.subTest(changes=changes),self.assertRaises(ValueError):
                self.check(b={**self.b,**changes})
    def test_reject_extra_fields_and_unsupported_duration(self):
        with self.assertRaises(ValueError):
            self.check(b={**self.b,"unrecognized":"fixture"})
        for duration in (600,1800,True):
            with self.assertRaises(ValueError):
                validate(self.a,self.b,**{**self.stage,"duration":duration})
if __name__=="__main__": unittest.main()
