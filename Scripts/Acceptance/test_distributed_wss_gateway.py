import asyncio
import base64
import datetime
import ipaddress
import json
import os
from pathlib import Path
import ssl
import tempfile
import unittest
from unittest.mock import patch
from cryptography import x509
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID
from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed
from distributed_audio_relay import RelayContract
from distributed_role_provisioning import generate
from audio_fixture.audio_websocket import ManagedAudioListener
from distributed_wss_gateway import LoopbackWSSGateway

def certificates(root):
    now=datetime.datetime.now(datetime.timezone.utc)
    ca=ec.generate_private_key(ec.SECP256R1())
    ca_name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,"V64 disposable test root")])
    authority=(x509.CertificateBuilder().subject_name(ca_name).issuer_name(ca_name).public_key(ca.public_key())
        .serial_number(x509.random_serial_number()).not_valid_before(now-datetime.timedelta(minutes=1))
        .not_valid_after(now+datetime.timedelta(minutes=20))
        .add_extension(x509.BasicConstraints(ca=True,path_length=0),critical=True)
        .add_extension(x509.SubjectKeyIdentifier.from_public_key(ca.public_key()),critical=False)
        .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(ca.public_key()),critical=False)
        .add_extension(x509.KeyUsage(digital_signature=False,content_commitment=False,key_encipherment=False,
            data_encipherment=False,key_agreement=False,key_cert_sign=True,crl_sign=True,encipher_only=False,decipher_only=False),critical=True)
        .sign(ca,hashes.SHA256()))
    key=ec.generate_private_key(ec.SECP256R1())
    leaf=(x509.CertificateBuilder().subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,"fixture")]))
        .issuer_name(ca_name).public_key(key.public_key()).serial_number(x509.random_serial_number())
        .not_valid_before(now-datetime.timedelta(minutes=1)).not_valid_after(now+datetime.timedelta(minutes=15))
        .add_extension(x509.SubjectAlternativeName([x509.IPAddress(ipaddress.ip_address("127.0.0.1"))]),critical=False)
        .add_extension(x509.BasicConstraints(ca=False,path_length=None),critical=True)
        .add_extension(x509.SubjectKeyIdentifier.from_public_key(key.public_key()),critical=False)
        .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(ca.public_key()),critical=False)
        .add_extension(x509.KeyUsage(digital_signature=True,content_commitment=False,key_encipherment=False,
            data_encipherment=False,key_agreement=False,key_cert_sign=False,crl_sign=False,encipher_only=False,decipher_only=False),critical=True)
        .add_extension(x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.SERVER_AUTH]),critical=False)
        .sign(ca,hashes.SHA256()))
    def write(name,data):
        path=Path(root)/name
        fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,"wb") as f: f.write(data)
        return path
    return (write("ca.pem",authority.public_bytes(serialization.Encoding.PEM)),
        write("leaf.pem",leaf.public_bytes(serialization.Encoding.PEM)),
        write("leaf-key.pem",key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption())))

class WSSGatewayTests(unittest.IsolatedAsyncioTestCase):
    async def test_verified_tls_role_authentication_and_shutdown(self):
        config,roles=generate("123:1",30,"https://127.0.0.1/")
        contract=RelayContract(config)
        with tempfile.TemporaryDirectory() as root,patch.dict(os.environ,{"IOSNEXT_EXPERIMENTAL_AUDIO":"true"}):
            ca,cert,key=certificates(root)
            listener=ManagedAudioListener(contract.broker(),0)
            gateway=LoopbackWSSGateway(listener.port,cert,key,lifetime=30)
            try:
                port=await gateway.start()
                url=f"wss://127.0.0.1:{port}/v1/audio"
                trust=ssl.create_default_context(cafile=str(ca))
                def open_ws(token,**kwargs):
                    return connect(url,ssl=trust,additional_headers={"Authorization":"Bearer "+token},
                        open_timeout=3,close_timeout=1,proxy=None,**kwargs)
                with self.assertRaises(ssl.SSLCertVerificationError):
                    async with connect(url,ssl=ssl.create_default_context(),open_timeout=3,proxy=None):
                        self.fail("unknown certificate accepted")
                with self.assertRaises(ssl.SSLCertVerificationError):
                    async with open_ws(roles["A"]["tokens"][0],server_hostname="wrong.invalid"):
                        self.fail("wrong hostname accepted")
                async with open_ws(roles["A"]["tokens"][0]) as a,open_ws(roles["B"]["tokens"][0]) as b:
                    for ws in (a,b):
                        await ws.send(json.dumps({"call_id":contract.call_id,"mode":"stream"}))
                        self.assertTrue(json.loads(await asyncio.wait_for(ws.recv(),3))["bound"])
                    await a.send(json.dumps({"action":"refresh","token":roles["A"]["tokens"][1]}))
                    self.assertTrue(json.loads(await asyncio.wait_for(a.recv(),3))["result"]["refreshed"])
                    await a.send(json.dumps({"action":"refresh","token":roles["B"]["tokens"][2]}))
                    with self.assertRaises(ConnectionClosed):
                        await asyncio.wait_for(a.recv(),3)
                    await gateway.close()
                    with self.assertRaises(ConnectionClosed):
                        await asyncio.wait_for(b.recv(),3)
                self.assertFalse(gateway.active)
                self.assertTrue(gateway.closed)
                with self.assertRaises(OSError):
                    await asyncio.open_connection("127.0.0.1",port)
            finally:
                await gateway.close()
                await asyncio.to_thread(listener.close)

if __name__=="__main__":
    unittest.main()
