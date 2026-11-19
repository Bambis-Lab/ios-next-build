"""Bounded loopback TLS gateway for the isolated synthetic audio relay.

No public listener, DNS routing, provisioning, or application trust override.
A separately authorized transport may forward to this endpoint only after
its own approval. This process never reads bearer or media contents.
"""
import asyncio
import ssl
import time

class LoopbackWSSGateway:
    def __init__(self, upstream_port, cert, key, *, lifetime=660):
        if type(upstream_port) is not int or not 1<=upstream_port<=65535:
            raise ValueError("invalid_upstream")
        if not 1<=lifetime<=1200:
            raise ValueError("invalid_lifetime")
        self.upstream_port=upstream_port
        self.lifetime=lifetime
        self.context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.context.minimum_version=ssl.TLSVersion.TLSv1_2
        self.context.load_cert_chain(cert,key)
        self.active=set()
        self.listener=None
        self.expiry_task=None
        self.deadline=None
        self.closed=False

    async def start(self):
        if self.listener is not None or self.closed:
            raise RuntimeError("single_use")
        self.deadline=time.monotonic()+self.lifetime
        self.listener=await asyncio.start_server(self._client,"127.0.0.1",0,
            ssl=self.context,ssl_handshake_timeout=3,ssl_shutdown_timeout=1,limit=32768)
        self.expiry_task=asyncio.create_task(self._expire())
        return self.listener.sockets[0].getsockname()[1]

    async def _expire(self):
        await asyncio.sleep(max(0,self.deadline-time.monotonic()))
        await self.close()

    @staticmethod
    async def _close_stream(stream):
        if stream is not None:
            stream.close()
            try:
                await asyncio.wait_for(stream.wait_closed(),timeout=2)
            except (OSError,TimeoutError,ssl.SSLError):
                pass

    async def _client(self, reader, writer):
        task=asyncio.current_task()
        if self.closed or len(self.active)>=8 or time.monotonic()>=self.deadline:
            await self._close_stream(writer)
            return
        self.active.add(task)
        upstream=None
        jobs=[]
        try:
            incoming,upstream=await asyncio.wait_for(
                asyncio.open_connection("127.0.0.1",self.upstream_port),timeout=2)
            async def pipe(source,destination):
                while data:=await source.read(16384):
                    destination.write(data)
                    await asyncio.wait_for(destination.drain(),timeout=2)
            jobs=[asyncio.create_task(pipe(reader,upstream)),asyncio.create_task(pipe(incoming,writer))]
            done,_=await asyncio.wait(jobs,timeout=max(0,self.deadline-time.monotonic()),
                return_when=asyncio.FIRST_COMPLETED)
            for job in done:
                job.result()
        except (OSError,TimeoutError,ssl.SSLError):
            pass
        finally:
            for job in jobs: job.cancel()
            await asyncio.gather(*jobs,return_exceptions=True)
            await asyncio.gather(self._close_stream(upstream),self._close_stream(writer))
            self.active.discard(task)

    async def close(self):
        if self.closed:
            return
        self.closed=True
        if self.listener is not None:
            self.listener.close()
            await self.listener.wait_closed()
        if self.expiry_task is not None and self.expiry_task is not asyncio.current_task():
            self.expiry_task.cancel()
            await asyncio.gather(self.expiry_task,return_exceptions=True)
        running=list(self.active)
        for task in running: task.cancel()
        if running:
            await asyncio.wait_for(asyncio.gather(*running,return_exceptions=True),timeout=5)
        if self.active:
            raise RuntimeError("gateway_shutdown_incomplete")
