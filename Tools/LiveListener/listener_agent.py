"""Darul Irfan live listener: carries the Paltalk zikr room to the stream hub.

Runs on a listener machine (prototype: a Windows PC; production: two cloud
Windows servers) where Paltalk Desktop is signed in with a listener account.

  1. Watches for the zikr room (OURSHEIKH by default). Paltalk lists it only
     while a session is running, and a joined room appears as a pane named
     "<room> ... - Paltalk", so the agent can tell when it is in the room.
  2. While in the room, captures what the machine plays (WASAPI loopback - on
     a dedicated listener that is only Paltalk), puts it over a still Daily
     Zikr frame (YouTube and Facebook need a picture), and streams it live.
  3. Restarts the encoder if it stops, and stops streaming when the room closes.
  4. Reports a heartbeat, so the server can alert admins if the listener dies.

Nothing is recorded here: the stream is live only.

Joining the room automatically (the paltalk:// link with the room's id, or
the room search) is added once the room has been observed during a session.

Usage:
  listener_agent.py --once-test 20           # 20 s test to a local file
  listener_agent.py --output srt://... [--backup rtmps://...]
"""

from __future__ import annotations

import argparse
import json
import queue
import shutil
import subprocess
import sys
import threading
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import pyaudiowpatch as pyaudio

HERE = Path(__file__).resolve().parent
FRAME = HERE / "daily_zikr_frame.png"
RATE, CHANNELS, CHUNK = 48_000, 2, 1_024


def log(message: str) -> None:
    print(f"{datetime.now().strftime('%H:%M:%S')} {message}", flush=True)


# MARK: - Room detection

def joined_room_title(room: str) -> str | None:
    """The title of the joined room's pane, or None when not in the room."""
    try:
        from pywinauto import Desktop
    except ImportError:
        return None
    wanted = room.lower()
    for window in Desktop(backend="uia").windows():
        try:
            if (window.element_info.name or "").lower() != "paltalk":
                continue
            for pane in window.descendants(control_type="Pane"):
                name = (pane.element_info.name or "")
                if wanted in name.lower() and name.lower().endswith("- paltalk"):
                    return name
        except Exception:  # noqa: BLE001 - the UI changes under us; try again next tick
            continue
    return None


# MARK: - Audio

class LoopbackAudio:
    """Feeds the default speaker's loopback into a queue of PCM chunks."""

    def __init__(self) -> None:
        self.audio = pyaudio.PyAudio()
        wasapi = self.audio.get_host_api_info_by_type(pyaudio.paWASAPI)
        default = self.audio.get_device_info_by_index(wasapi["defaultOutputDevice"])
        device = next((d for d in self.audio.get_loopback_device_info_generator() if default["name"] in d["name"]), None)
        if device is None:
            raise RuntimeError("No loopback device for the default output")
        self.rate = int(device["defaultSampleRate"])
        self.channels = int(device["maxInputChannels"])
        self.chunks: queue.Queue[bytes] = queue.Queue(maxsize=400)
        self.stream = self.audio.open(format=pyaudio.paInt16, channels=self.channels, rate=self.rate, input=True,
                                      input_device_index=device["index"], frames_per_buffer=CHUNK,
                                      stream_callback=self._callback)
        log(f"capturing {device['name']} at {self.rate} Hz, {self.channels} ch")

    def _callback(self, data, frames, info, status):  # noqa: ANN001 - PortAudio signature
        try:
            self.chunks.put_nowait(data)
        except queue.Full:
            pass  # the encoder fell behind; dropping beats unbounded delay on a live stream
        return (None, pyaudio.paContinue)

    def silence(self, seconds: float) -> bytes:
        return b"\x00" * int(self.rate * seconds) * self.channels * 2

    def close(self) -> None:
        self.stream.close()
        self.audio.terminate()


# MARK: - Encoder

def ensure_frame() -> None:
    """A plain branded frame. Text only, no platform names."""
    if FRAME.exists():
        return
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-f", "lavfi", "-i", "color=c=0x0B3B2C:s=1280x720",
        "-vf", ("drawtext=fontfile='C\\:/Windows/Fonts/segoeuib.ttf':text='Daily Zikr':fontcolor=white:fontsize=96:"
                "x=(w-text_w)/2:y=(h-text_h)/2-50,"
                "drawtext=fontfile='C\\:/Windows/Fonts/segoeui.ttf':text='Darul Irfan · Silsila Naqshbandia Owaisiah':"
                "fontcolor=0xE9C46A:fontsize=40:x=(w-text_w)/2:y=(h-text_h)/2+70"),
        "-frames:v", "1", str(FRAME),
    ], check=True)


def encoder_command(audio: LoopbackAudio, output: str) -> list[str]:
    """Still frame + live audio, as a stream YouTube and Facebook accept:
    H.264 keyframes every 2 s, AAC 128 kb/s, constant frame rate."""
    command = [
        "ffmpeg", "-hide_banner", "-loglevel", "warning", "-nostats",
        "-re", "-loop", "1", "-framerate", "15", "-i", str(FRAME),
        "-f", "s16le", "-ar", str(audio.rate), "-ch_layout", "stereo" if audio.channels == 2 else "mono", "-i", "pipe:0",
        "-map", "0:v", "-map", "1:a",
        "-c:v", "libx264", "-preset", "veryfast", "-tune", "stillimage", "-pix_fmt", "yuv420p",
        "-r", "15", "-g", "30", "-b:v", "400k", "-maxrate", "400k", "-bufsize", "800k",
        "-c:a", "aac", "-b:a", "128k", "-ar", "48000",
    ]
    if output.startswith("srt://"):
        command += ["-f", "mpegts", output]
    elif output.startswith(("rtmp://", "rtmps://")):
        command += ["-f", "flv", output]
    else:
        command += ["-f", "mpegts", output]
    return command


class Encoder:
    """One ffmpeg process fed from the audio queue; restarted if it dies."""

    def __init__(self, audio: LoopbackAudio, output: str) -> None:
        self.audio, self.output = audio, output
        self.process: subprocess.Popen | None = None
        self.running = False
        self.thread: threading.Thread | None = None

    def start(self) -> None:
        self.running = True
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def _run(self) -> None:
        while self.running:
            log(f"encoder starting -> {redact(self.output)}")
            self.process = subprocess.Popen(encoder_command(self.audio, self.output), stdin=subprocess.PIPE)
            started = time.time()
            try:
                while self.running and self.process.poll() is None:
                    try:
                        chunk = self.audio.chunks.get(timeout=0.5)
                    except queue.Empty:
                        # Keep the stream alive through a pause in the room.
                        chunk = self.audio.silence(0.5)
                    self.process.stdin.write(chunk)
            except (BrokenPipeError, OSError):
                pass
            if self.running:
                code = self.process.poll()
                log(f"encoder stopped (code {code}); restarting")
                # Back off a little if it fails straight away (bad key, no network).
                time.sleep(2 if time.time() - started > 30 else 10)

    def stop(self) -> None:
        self.running = False
        if self.process and self.process.poll() is None:
            try:
                self.process.stdin.close()
            except OSError:
                pass
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()


def redact(url: str) -> str:
    """Stream keys never go into logs."""
    return url.split("?")[0].rsplit("/", 1)[0] + "/…" if "/" in url else url


# MARK: - Heartbeat

def heartbeat(endpoint: str | None, token: str | None, state: dict) -> None:
    if not endpoint or not token:
        return
    body = json.dumps({**state, "at": datetime.now(timezone.utc).isoformat()}).encode()
    request = urllib.request.Request(endpoint, data=body, method="POST",
                                     headers={"content-type": "application/json", "authorization": f"Bearer {token}"})
    try:
        urllib.request.urlopen(request, timeout=10).close()
    except Exception:  # noqa: BLE001 - a missed heartbeat is itself the signal
        pass


# MARK: - Main

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--room", default="oursheikh")
    parser.add_argument("--output", help="srt:// (hub) or rtmps:// (direct) destination")
    parser.add_argument("--heartbeat-url")
    parser.add_argument("--heartbeat-token")
    parser.add_argument("--listener-id", default="listener-a")
    parser.add_argument("--once-test", type=int, metavar="SECONDS",
                        help="stream SECONDS of whatever is playing to a local test file, then stop")
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    if not shutil.which("ffmpeg"):
        log("ffmpeg is not installed")
        return 2
    ensure_frame()
    audio = LoopbackAudio()

    if args.once_test:
        out = HERE / "test_stream.ts"
        encoder = Encoder(audio, str(out))
        encoder.start()
        time.sleep(args.once_test)
        encoder.stop()
        audio.close()
        log(f"test stream written: {out} ({out.stat().st_size // 1024} KB)")
        return 0

    if not args.output:
        parser.error("--output is required outside --once-test")
    encoder: Encoder | None = None
    try:
        while True:
            title = joined_room_title(args.room)
            if title and encoder is None:
                log(f"in the room ({title}); going live")
                encoder = Encoder(audio, args.output)
                encoder.start()
            elif not title and encoder is not None:
                log("room closed or left; stopping")
                encoder.stop()
                encoder = None
            heartbeat(args.heartbeat_url, args.heartbeat_token,
                      {"listener": args.listener_id, "inRoom": bool(title), "streaming": encoder is not None})
            time.sleep(10)
    except KeyboardInterrupt:
        pass
    finally:
        if encoder:
            encoder.stop()
        audio.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
