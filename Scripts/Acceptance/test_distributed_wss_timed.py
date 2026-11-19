"""Actual continuous 30/120/300s control using two Python clients, not native G03.

No external network or real family data. Exact media frames, peer
authentication, TLS, refresh and monotonic elapsed time are checked.
"""
import asyncio
import base64
import json
import os
import ssl
import struct
import tempfile
import unittest
from unittest.mock import patch
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from websockets.asyncio.client import connect
from distributed_role_provisioning import generate
from distributed_audio_relay import RelayContract, ROLES
from distributed_wss_gateway import LoopbackWSSGateway
from test_distributed_wss_gateway import certificates
from audio_fixture.audio_websocket import ManagedAudioListener
from audio_fixture.audio_crypto_reference import offer, establish, public

DURATION=int(os.environ.get("IOSNEXT_LOCAL_WSS_DURATION","30"))
if DURATION not in (30,120,300):
    raise SystemExit("unsupported control duration")
TARGET=DURATION*50

def b64(value):
    return base64.b64encode(value).decode("ascii")

def unb64(value):
    return base64.b64decode(value,validate=True)

def frame(sequence,marker):
    return struct.pack(">Q",sequence)+bytes([marker])*632

class TimedWSSControl(unittest.IsolatedAsyncioTestCase):
    async def test_continuous_bidirectional_encrypted_wss(self):
        async with asyncio.timeout(DURATION+70):
            await self.exercise()

    async def exercise(self):
        relay,roles=generate("123:1",DURATION,"https://127.0.0.1/")
        contract=RelayContract(relay)
        with tempfile.TemporaryDirectory() as root,patch.dict(os.environ,{"IOSNEXT_EXPERIMENTAL_AUDIO":"true"}):
            ca,cert,key=certificates(root)
            server=ManagedAudioListener(contract.broker(),0)
            gateway=LoopbackWSSGateway(server.port,cert,key,lifetime=DURATION+70)
            try:
                port=await gateway.start()
                trust=ssl.create_default_context(cafile=str(ca))
                def ws(role):
                    return connect(f"wss://127.0.0.1:{port}/v1/audio",ssl=trust,
                        additional_headers={"Authorization":"Bearer "+roles[role]["tokens"][0]},
                        proxy=None,open_timeout=3,close_timeout=1)
                async with ws("A") as a,ws("B") as b:
                    sockets={"A":a,"B":b}
                    caller,callee=ROLES["A"],ROLES["B"]
                    eph={r:X25519PrivateKey.generate() for r in ROLES}
                    for role,sock in sockets.items():
                        await sock.send(json.dumps({"call_id":contract.call_id,"mode":"stream"}))
                        self.assertEqual(json.loads(await asyncio.wait_for(sock.recv(),3)),{"bound":True,"mode":"stream"})
                        signing=Ed25519PrivateKey.from_private_bytes(unb64(roles[role]["signingSeed"]))
                        k,s=offer(contract.call_id,caller,callee,ROLES[role],eph[role],signing)
                        await sock.send(json.dumps({"action":"offer","ephemeral":b64(k),"signature":b64(s)}))
                        self.assertTrue(json.loads(await asyncio.wait_for(sock.recv(),3))["result"]["published"])
                    codecs={}
                    for role,sock in sockets.items():
                        await sock.send(json.dumps({"action":"peer_offer"}))
                        p=json.loads(await asyncio.wait_for(sock.recv(),3))["result"]["offer"]
                        codecs[role]=establish(contract.call_id,caller,callee,ROLES[role],
                            eph[role],unb64(p["ephemeral"]),unb64(p["signature"]),unb64(roles[role]["peerSigningKey"]))
                    barrier=asyncio.Barrier(2)
                    async def client(role):
                        sock=sockets[role]
                        codec=codecs[role]
                        marker,other=(31,73) if role=="A" else (73,31)
                        received=0
                        async def incoming():
                            nonlocal received
                            value=json.loads(await asyncio.wait_for(sock.recv(),5))
                            if value.get("event")=="audio":
                                for packet in value["packets"]:
                                    self.assertEqual(packet["sequence"],received)
                                    self.assertTrue(codec.open(received,unb64(packet["ciphertext"]))==frame(received,other))
                                    received+=1
                                return None
                            self.assertEqual(value.get("status"),200)
                            return value["result"]
                        async def command(payload):
                            await sock.send(json.dumps(payload))
                            while True:
                                result=await incoming()
                                if result is not None:
                                    return result
                        async def push(sequence):
                            result=await command({"action":"push","sequence":sequence,
                                "ciphertext":b64(codec.seal(sequence,frame(sequence,marker)))})
                            self.assertTrue(result["queued"])
                        await push(0)
                        while received==0:
                            self.assertIsNone(await incoming())
                        await barrier.wait()
                        clock=asyncio.get_running_loop()
                        start=clock.time()
                        renewals=0
                        sent=0
                        max_lateness=0.0
                        for sequence in range(1,TARGET+1):
                            scheduled=start+sequence/50
                            await asyncio.sleep(max(0,scheduled-clock.time()))
                            if sequence in (TARGET//3,2*TARGET//3):
                                renewals+=1
                                result=await command({"action":"refresh","token":roles[role]["tokens"][renewals]})
                                self.assertTrue(result["refreshed"])
                                self.assertEqual(result["expires_at"],roles[role]["grantExpiries"][renewals])
                            await push(sequence)
                            sent+=1
                            max_lateness=max(max_lateness,clock.time()-scheduled)
                        elapsed=clock.time()-start
                        self.assertGreaterEqual(elapsed,DURATION)
                        await command({"action":"heartbeat"})
                        while received<TARGET+1:
                            self.assertIsNone(await incoming())
                        self.assertEqual(received,TARGET+1)
                        self.assertEqual(sent,TARGET)
                        self.assertEqual(renewals,2)
                        self.assertLessEqual(max_lateness,2.0,"timed control fell more than 2s behind schedule")
                        await barrier.wait()
                        await command({"action":"heartbeat"})
                        self.assertEqual(received,TARGET+1)
                        return {"role":role,"sent":sent,"received":received-1,
                                "elapsed_seconds":round(elapsed,4),"renewals":renewals,
                                "max_send_lateness_ms":round(max_lateness*1000,3)}
                    async with asyncio.TaskGroup() as group:
                        left=group.create_task(client("A"))
                        right=group.create_task(client("B"))
                    print(json.dumps({"status":"PASS_LOCAL_PYTHON_CONTROL","native":False,
                        "duration_seconds":DURATION,"clients":[left.result(),right.result()]}))
            finally:
                await gateway.close()
                await asyncio.to_thread(server.close)

if __name__=="__main__":
    unittest.main(verbosity=2)
