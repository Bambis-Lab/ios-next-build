"""Experimental opaque audio packet buffer, not an audio codec or E2EE handshake.

Only an authenticated call adapter may use this component, after checking
accepted call state and both device identities. No sockets or plaintext.
"""
import base64
import threading
import time
from collections import deque

class AudioPacketBuffer:
    def __init__(self, participants, clock=time.monotonic, max_frames=50, ttl=2.0):
        if len(participants)!=2 or participants[0]==participants[1]:
            raise ValueError("invalid_participants")
        if not 1<=max_frames<=100 or not 0<ttl<=5:
            raise ValueError("invalid_limits")
        self.participants=tuple(participants)
        self.clock=clock
        self.ttl=ttl
        self.max_frames=max_frames
        self.queues={p:deque() for p in participants}
        self.highest={p:-1 for p in participants}
        self.lock=threading.Lock()
        self.closed=False

    def _authorize(self,actor):
        if self.closed or actor not in self.participants:
            raise PermissionError("audio_unavailable")

    def _purge(self,queue):
        now=self.clock()
        while queue and queue[0][0]<=now:
            queue.popleft()

    def push(self,actor,sequence,ciphertext):
        with self.lock:
            self._authorize(actor)
            if type(sequence) is not int or not 0<=sequence<2**63:
                raise ValueError("invalid_sequence")
            if sequence<=self.highest[actor]:
                raise ValueError("replayed_packet")
            if not isinstance(ciphertext,str) or len(ciphertext)>8192:
                raise ValueError("invalid_packet")
            try:
                raw=base64.b64decode(ciphertext,validate=True)
            except ValueError:
                raise ValueError("invalid_packet") from None
            if not 16<=len(raw)<=4096:
                raise ValueError("invalid_packet")
            peer=next(p for p in self.participants if p!=actor)
            queue=self.queues[peer]
            self._purge(queue)
            if len(queue)>=self.max_frames:
                queue.popleft()
            queue.append((self.clock()+self.ttl,{"sequence":sequence,"ciphertext":ciphertext}))
            self.highest[actor]=sequence

    def drain(self,actor,limit=20):
        with self.lock:
            self._authorize(actor)
            if type(limit) is not int or not 1<=limit<=50:
                raise ValueError("invalid_limit")
            queue=self.queues[actor]
            self._purge(queue)
            return [queue.popleft()[1] for _ in range(min(limit,len(queue)))]

    def close(self):
        with self.lock:
            self.closed=True
            for queue in self.queues.values():
                queue.clear()
