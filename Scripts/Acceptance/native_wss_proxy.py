"""Test-only TLS termination. Loopback, bounded sockets, no payload logging."""
import asyncio
import ssl
import sys
from pathlib import Path

async def main(directory):
    active=set()
    async def client(reader,writer):
        task=asyncio.current_task()
        if len(active)>=8:
            writer.close()
            await writer.wait_closed()
            return
        active.add(task)
        upstream=None
        jobs=[]
        try:
            incoming,upstream=await asyncio.wait_for(asyncio.open_connection("127.0.0.1",18766),timeout=2)
            async def pipe(source,destination):
                while data:=await source.read(16384):
                    destination.write(data)
                    await asyncio.wait_for(destination.drain(),timeout=2)
            jobs=[asyncio.create_task(pipe(reader,upstream)),asyncio.create_task(pipe(incoming,writer))]
            done,_=await asyncio.wait(jobs,return_when=asyncio.FIRST_COMPLETED)
            for job in done:
                job.result()
        except (OSError,TimeoutError,ssl.SSLError):
            pass
        finally:
            for job in jobs:
                job.cancel()
            await asyncio.gather(*jobs,return_exceptions=True)
            for stream in (upstream,writer):
                if stream is not None:
                    stream.close()
                    try:
                        await asyncio.wait_for(stream.wait_closed(),timeout=2)
                    except (OSError,TimeoutError,ssl.SSLError):
                        pass
            active.discard(task)
    listeners=[]
    try:
        for port,name in ((18767,"good"),(18768,"wrong")):
            tls=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            tls.minimum_version=ssl.TLSVersion.TLSv1_2
            tls.load_cert_chain(directory/(name+".crt"),directory/(name+".key"))
            listeners.append(await asyncio.start_server(client,"127.0.0.1",port,ssl=tls,
                ssl_handshake_timeout=3,ssl_shutdown_timeout=1,limit=32768))
        print("SYNTHETIC_WSS_READY",flush=True)
        await asyncio.gather(*(listener.serve_forever() for listener in listeners))
    finally:
        for listener in listeners:
            listener.close()
            await listener.wait_closed()

if __name__=="__main__":
    asyncio.run(main(Path(sys.argv[1])))
