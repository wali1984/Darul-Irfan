"""Audio plumbing for the relay: 48 kHz stereo 16-bit everywhere.

    SFU track  --(pull)-->  PcmBuffer  -->  virtual cable into Paltalk's mic
    Paltalk's speaker cable  -->  PcmBuffer  --(publish)-->  SFU track
    whichever is on air  -->  programme PcmBuffer  -->  ffmpeg  -->  YouTube
"""

from __future__ import annotations

import asyncio
import fractions
import math
import threading
import time
from collections import deque

import numpy as np
from av import AudioFrame, AudioResampler
from aiortc import MediaStreamTrack
from aiortc.mediastreams import MediaStreamError

RATE = 48_000
CHANNELS = 2
FRAME = 960  # 20 ms


class PcmBuffer:
    """A bounded FIFO of int16 stereo samples. Readers get silence when it
    runs dry; writers drop the oldest audio when it overfills, so delay never
    builds up on a live stream."""

    def __init__(self, max_seconds: float = 1.0) -> None:
        self.max_frames = int(RATE * max_seconds)
        self.chunks: deque[np.ndarray] = deque()
        self.frames = 0
        self.lock = threading.Lock()
        self.peak = 0
        self.last_sound = 0.0

    def write(self, samples: np.ndarray) -> None:
        if samples.size == 0:
            return
        loudest = int(np.abs(samples[::8]).max())
        with self.lock:
            self.peak = max(self.peak, loudest)
            if loudest >= 200:
                self.last_sound = time.time()
            self.chunks.append(samples)
            self.frames += len(samples)
            while self.frames > self.max_frames and self.chunks:
                self.frames -= len(self.chunks.popleft())

    def read(self, frames: int) -> np.ndarray:
        out = np.zeros((frames, CHANNELS), dtype=np.int16)
        filled = 0
        with self.lock:
            while filled < frames and self.chunks:
                chunk = self.chunks[0]
                take = min(frames - filled, len(chunk))
                out[filled:filled + take] = chunk[:take]
                filled += take
                if take == len(chunk):
                    self.chunks.popleft()
                else:
                    self.chunks[0] = chunk[take:]
                self.frames -= take
        return out

    def clear(self) -> None:
        with self.lock:
            self.chunks.clear()
            self.frames = 0

    def take_peak(self) -> int:
        with self.lock:
            peak, self.peak = self.peak, 0
        return peak


def _frame(samples: np.ndarray, pts: int) -> AudioFrame:
    frame = AudioFrame.from_ndarray(samples.reshape(1, -1), format="s16", layout="stereo")
    frame.sample_rate = RATE
    frame.pts = pts
    frame.time_base = fractions.Fraction(1, RATE)
    return frame


class BufferTrack(MediaStreamTrack):
    """An outgoing WebRTC audio track read from a PcmBuffer in real time."""

    kind = "audio"

    def __init__(self, buffer: PcmBuffer) -> None:
        super().__init__()
        self.buffer = buffer
        self.pts = 0
        self.start: float | None = None

    async def recv(self) -> AudioFrame:
        if self.readyState != "live":
            raise MediaStreamError
        if self.start is None:
            self.start = time.time()
        wait = self.start + self.pts / RATE - time.time()
        if wait > 0:
            await asyncio.sleep(wait)
        frame = _frame(self.buffer.read(FRAME), self.pts)
        self.pts += FRAME
        return frame


class ToneTrack(BufferTrack):
    """A test tone, for checks without a microphone."""

    def __init__(self, hz: float = 440.0) -> None:
        super().__init__(PcmBuffer())
        self.hz = hz

    async def recv(self) -> AudioFrame:
        t = (np.arange(FRAME) + self.pts) / RATE
        wave = (np.sin(2 * math.pi * self.hz * t) * 9000).astype(np.int16)
        self.buffer.write(np.stack([wave, wave], axis=1))
        return await super().recv()


async def drain(track, *buffers: PcmBuffer) -> None:
    """Copies an incoming WebRTC track into buffers until the track ends."""
    resampler = AudioResampler(format="s16", layout="stereo", rate=RATE)
    while True:
        try:
            frame = await track.recv()
        except MediaStreamError:
            return
        for converted in resampler.resample(frame):
            samples = converted.to_ndarray().reshape(-1, CHANNELS)
            for buffer in buffers:
                buffer.write(samples)


def find_device(name: str, output: bool) -> int:
    """A device whose name contains `name`, on the MME host API (which
    converts sample rates for us)."""
    import sounddevice as sd
    apis = sd.query_hostapis()
    wanted = name.lower()
    matches = []
    for index, device in enumerate(sd.query_devices()):
        channels = device["max_output_channels"] if output else device["max_input_channels"]
        if channels and wanted in device["name"].lower():
            # A name that starts with what was asked for first: "CABLE Output"
            # is also inside "Hi-Fi Cable Output", the silent mic cable, and
            # on the Contabo server (9 November) that one was listed first -
            # the room was captured as silence through a whole Tahajjud start.
            matches.append((not device["name"].lower().startswith(wanted), apis[device["hostapi"]]["name"] != "MME", index))
    if not matches:
        raise RuntimeError(f"no {'output' if output else 'input'} device named like {name!r}")
    return sorted(matches)[0][-1]


class DeviceOutput:
    """Plays a PcmBuffer to an output device (the cable into Paltalk's mic)."""

    def __init__(self, name: str, buffer: PcmBuffer) -> None:
        import sounddevice as sd
        self.buffer = buffer
        self.stream = sd.OutputStream(device=find_device(name, True), samplerate=RATE, channels=CHANNELS,
                                      dtype="int16", blocksize=FRAME, callback=self._callback)
        self.stream.start()

    def _callback(self, outdata, frames, info, status) -> None:  # noqa: ANN001 - PortAudio signature
        outdata[:] = self.buffer.read(frames)

    def close(self) -> None:
        self.stream.stop()
        self.stream.close()


class DeviceInput:
    """Records an input device (Paltalk's speaker cable) into PcmBuffers."""

    def __init__(self, name: str, *buffers: PcmBuffer, tap=None) -> None:  # noqa: ANN001
        import sounddevice as sd
        self.buffers, self.tap = buffers, tap
        self.stream = sd.InputStream(device=find_device(name, False), samplerate=RATE, channels=CHANNELS,
                                     dtype="int16", blocksize=FRAME, callback=self._callback)
        self.stream.start()

    def _callback(self, indata, frames, info, status) -> None:  # noqa: ANN001 - PortAudio signature
        samples = indata.copy()
        for buffer in self.buffers:
            buffer.write(samples)
        if self.tap:
            self.tap(samples)

    def close(self) -> None:
        self.stream.stop()
        self.stream.close()
