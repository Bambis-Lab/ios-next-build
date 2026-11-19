"""Native acceptance fixture; never launched by the application.
Synthetic-only identities and credentials. Exact pinned backend audio modules.
"""
import base64, hashlib, json, os, sys
from pathlib import Path
from types import SimpleNamespace
from cryptography.hazmat.primitives.asymmetric import ed25519, x25519
from audio_fixture.audio_crypto_reference import public, offer, establish
from audio_fixture.audio_websocket import audio_websocket
from audio_fixture.call_signalling import CallSignalling

A=("ha-fixture-a","ios-a")
B=("ha-fixture-b","ios-b")
CID="a"*32
PORT=18766
SIGN_A=bytes([11])*32
SIGN_B=bytes([12])*32
KEY_A=bytes([21])*32
KEY_B=bytes([22])*32
HASHES={
    "audio_websocket.py":"f2be6ec637f061afd8da26d35ed4d0b51a51d0bd",
    "audio_session.py":"ee9fe984f62d4f93e3b02ecc4c2d862fd0676f3b",
    "audio_packet_buffer.py":"527a42cc56d6adaf25a146bc7faaeeed9d96d651",
    "call_signalling.py":"fb8d0baed90c97b1655351001de8a9cb9fed416a",
    "audio_crypto_reference.py":"c4879b248a33e2e1f33aa1334f88c088b9d54e0f",
}
def verify():
    for name, expected in HASHES.items():
        raw=(Path(__file__).parent/"audio_fixture"/name).read_bytes()
        digest=hashlib.sha1(("blob %d\0"%len(raw)).encode()+raw).hexdigest()
        if digest!=expected:
            raise RuntimeError("audio fixture source drift: "+name)

def b64(data): return base64.b64encode(data).decode("ascii")
def keys():
    return (ed25519.Ed25519PrivateKey.from_private_bytes(SIGN_A),
            ed25519.Ed25519PrivateKey.from_private_bytes(SIGN_B))
def generate(destination, secure=False):
    sa,sb=keys()
    ka=x25519.X25519PrivateKey.from_private_bytes(KEY_A)
    kb=x25519.X25519PrivateKey.from_private_bytes(KEY_B)
    pa,aa=offer(CID,A,B,A,ka,sa)
    pb,ab=offer(CID,A,B,B,kb,sb)
    left=establish(CID,A,B,A,ka,pb,ab,public(sb))
    right=establish(CID,A,B,B,kb,pa,aa,public(sa))
    frame=bytes([7])*640
    packet_a=left.seal(0,frame)
    packet_b=right.seal(0,frame)
    assert right.open(0,packet_a)==left.open(0,packet_b)==frame
    values={"OFFER_A":b64(pa),"SIGNATURE_A":b64(aa),"OFFER_B":b64(pb),
            "SIGNATURE_B":b64(ab),"PACKET_A":b64(packet_a),"PACKET_B":b64(packet_b)}
    template=(Path(__file__).parent/"FamilyAudioNetworkTests.swift.in").read_text()
    for name,value in values.items():
        token="@"+name+"@"
        assert template.count(token)==1, name
        template=template.replace(token,value)
    if secure:
        template=template.replace("http://127.0.0.1:18766/","https://127.0.0.1:18767/")
        template=template.replace("ws://127.0.0.1:18766/v1/audio","wss://127.0.0.1:18767/v1/audio")
        template=template.replace("syntheticLoopback: true","syntheticLoopback: false")
        template=template.replace("// @TLS_PROBE@", """let wrongBase = try XCTUnwrap(URL(string: "https://127.0.0.1:18768/"))
        let wrongEndpoint = try XCTUnwrap(URL(string: "wss://127.0.0.1:18768/v1/audio"))
        let wrong = try FamilyAudioWire(configuration: .init(baseURL: wrongBase, token: "fixture-a", userID: a[0], deviceID: a[1]),
            endpoint: wrongEndpoint, context: ca)
        do {
            try await wrong.connect()
            XCTFail("Wrong-host certificate accepted")
        } catch {}
        XCTAssertFalse(wrong.isConnected)
        wrong.close()""")
    Path(destination).write_text(template)
    print("Python audio vectors generated from verified backend source")

def serve():
    import time
    os.environ["IOSNEXT_EXPERIMENTAL_AUDIO"]="true"
    sa,sb=keys()
    claims={"fixture-a":SimpleNamespace(user_id=A[0],device_id=A[1],family_device=True,expires_at=100),
            "fixture-b":SimpleNamespace(user_id=B[0],device_id=B[1],family_device=True,expires_at=100),
            "fixture-a-renewed":SimpleNamespace(user_id=A[0],device_id=A[1],family_device=True,expires_at=200),
            "fixture-b-renewed":SimpleNamespace(user_id=B[0],device_id=B[1],family_device=True,expires_at=200),
            "fixture-foreign":SimpleNamespace(user_id="foreign",device_id="ios-foreign",family_device=True,expires_at=100)}
    registry=SimpleNamespace(is_active=lambda u,d:(u,d) in (A,B))
    identities={A[0]:[{"device_id":A[1],"signing_public_key":b64(public(sa))}],
                B[0]:[{"device_id":B[1],"signing_public_key":b64(public(sb))}]}
    calls=CallSignalling()
    # Only this synthetic acceptance fixture manufactures an already accepted call.
    calls.calls[CID]={"id":CID,"caller":A,"callee":B,"state":"accepted","expires":time.monotonic()+600}
    broker=SimpleNamespace(family_registry=registry,bootstrap_issuer=SimpleNamespace(verify=claims.get),
                           store=SimpleNamespace(chat_identities=lambda u:identities.get(u,[])),calls=calls)
    with audio_websocket(broker,port=PORT) as server:
        print("SYNTHETIC_AUDIO_READY",flush=True)
        server.serve_forever()

if __name__=="__main__":
    verify()
    if len(sys.argv)==3 and sys.argv[1] in ("generate","generate-wss"):
        generate(sys.argv[2], secure=sys.argv[1]=="generate-wss")
    elif sys.argv[1:]==["serve"]:
        serve()
    else:
        raise SystemExit("generate DEST or serve")
