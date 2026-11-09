"""The programme for YouTube and Facebook: the stage picture plus the
programme audio, one ffmpeg for the whole session so each platform sees one
continuous broadcast.

ffmpeg reads a looping still image only once, so the picture is fed to it
instead: the current PNG (already scaled to 1280x720) is sent over a local
socket once a second (image2pipe), and replacing it changes the video within
a second. The stream runs at 5 frames a second with a keyframe every 2 s: a
still picture needs no more, and the relay server's processor is small
(15 fps with a 1920x1080 PNG decoded five times a second cost a fifth of it).
The audio arrives on stdin as 48 kHz stereo PCM; silence fills any gap.
Both outputs go through one encode (tee), and one failing platform does not
stop the other.
"""

from __future__ import annotations

import shutil
import socket
import subprocess
import threading
import time
from pathlib import Path

from audio_io import FRAME, RATE, PcmBuffer

LOG_FILE = Path(__file__).with_name("programme.log")
PICTURE_FPS = 1
OUTPUT_FPS = 10  # a still picture needs few frames; YouTube's preview needs a steady bitrate, not many
WIDTH, HEIGHT = 1280, 720


def fit(png: bytes) -> bytes:
    """The picture scaled to 1280x720 once, so ffmpeg never has to."""
    try:
        import io
        from PIL import Image
        image = Image.open(io.BytesIO(png)).convert("RGB")
        if image.size != (WIDTH, HEIGHT):
            image.thumbnail((WIDTH, HEIGHT))
            canvas = Image.new("RGB", (WIDTH, HEIGHT), (4, 21, 15))
            canvas.paste(image, ((WIDTH - image.width) // 2, (HEIGHT - image.height) // 2))
            image = canvas
        out = io.BytesIO()
        image.save(out, format="PNG", compress_level=1)
        return out.getvalue()
    except Exception:  # noqa: BLE001 - ffmpeg scales it itself
        return png


def log(message: str) -> None:
    print(f"{time.strftime('%H:%M:%S')} [programme] {message}", flush=True)


def last_lines(count: int = 2) -> str:
    """ffmpeg's last messages, keys removed."""
    try:
        lines = [line.strip() for line in LOG_FILE.read_text(encoding="utf-8", errors="replace").splitlines() if line.strip()]
    except OSError:
        return "-"
    import re
    return " | ".join(re.sub(r"(live2|app)/[^\s'\"]+", r"\1/…", line)[:160] for line in lines[-count:]) or "-"


def redact(url: str) -> str:
    """Stream keys never reach the log."""
    return url.rsplit("/", 1)[0] + "/…" if "://" in url else url


class Programme:
    def __init__(self, outputs: list[str], picture: Path) -> None:
        self.outputs = [o for o in outputs if o]
        self.buffer = PcmBuffer(max_seconds=2)
        self.picture = fit(picture.read_bytes())
        self.process: subprocess.Popen | None = None
        self.running = False
        self.state = "off"

    def set_picture(self, png: bytes) -> None:
        self.picture = fit(png)

    def start(self) -> None:
        if self.running or not self.outputs:
            return
        self.running = True
        threading.Thread(target=self._run, daemon=True).start()

    def stop(self) -> None:
        self.running = False

    def connected(self) -> bool:
        """ffmpeg holds a connection to a stream server (RTMP 1935 or RTMPS 443)."""
        try:
            import psutil
            return any(c.status == "ESTABLISHED" and c.raddr and c.raddr.port in (1935, 443)
                       for c in psutil.Process(self.process.pid).net_connections(kind="tcp"))
        except Exception:  # noqa: BLE001
            return False

    def _command(self, port: int) -> list[str]:
        ffmpeg = shutil.which("ffmpeg") or r"C:\ffmpeg\bin\ffmpeg.exe"
        if len(self.outputs) == 1 and "://" not in self.outputs[0]:
            sink = ["-f", "mpegts", self.outputs[0]]  # a file, for tests
        else:
            targets = "|".join(f"[f=flv:onfail=ignore]{url}" for url in self.outputs)
            sink = ["-f", "tee", targets]
        return [
            ffmpeg, "-hide_banner", "-loglevel", "warning", "-nostats", "-y",
            "-f", "image2pipe", "-framerate", str(PICTURE_FPS), "-i", f"tcp://127.0.0.1:{port}?listen=1",
            "-f", "s16le", "-ar", str(RATE), "-ac", "2", "-i", "pipe:0",
            "-map", "0:v", "-map", "1:a",
            "-vf", f"scale={WIDTH}:{HEIGHT}:force_original_aspect_ratio=decrease,pad={WIDTH}:{HEIGHT}:(ow-iw)/2:(oh-ih)/2,fps={OUTPUT_FPS}",
            "-c:v", "libx264", "-preset", "veryfast", "-tune", "stillimage", "-pix_fmt", "yuv420p",
            # Constant 1.5 Mbps with filler: a still picture would otherwise
            # send ~130 kbps and YouTube never finishes "preparing the stream"
            # (6 November). Filler bits cost no CPU.
            "-g", str(OUTPUT_FPS * 2), "-b:v", "1500k", "-minrate", "1500k", "-maxrate", "1500k", "-bufsize", "3000k",
            "-x264-params", "nal-hrd=cbr:force-cfr=1",
            "-c:a", "aac", "-b:a", "128k", "-ar", "48000",
            *sink,
        ]

    def _feed_picture(self, port: int, started: float) -> None:
        sock = None
        for _ in range(100):  # ffmpeg needs a moment to start listening
            try:
                sock = socket.create_connection(("127.0.0.1", port), timeout=5)
                break
            except OSError:
                time.sleep(0.1)
        if sock is None:
            log("ffmpeg never opened the picture input")
            return
        sent = 0
        try:
            while self.running and self.process and self.process.poll() is None:
                due = started + sent / PICTURE_FPS
                wait = due - time.time()
                if wait > 0:
                    time.sleep(wait)
                sock.sendall(self.picture)
                sent += 1
        except OSError:
            pass
        finally:
            sock.close()

    def _run(self) -> None:
        while self.running:
            self.state = "connecting"
            with socket.socket() as probe:
                probe.bind(("127.0.0.1", 0))
                port = probe.getsockname()[1]
            log(f"encoder starting -> {', '.join(redact(o) for o in self.outputs)}")
            # ffmpeg's own messages (a refused stream key, a dropped
            # connection) go to programme.log: on 6 November nothing reached
            # YouTube and nothing said why.
            errors = open(LOG_FILE, "a", encoding="utf-8", errors="replace")  # noqa: SIM115 - closed below
            errors.write(f"--- {time.strftime('%Y-%m-%d %H:%M:%S')} encoder starting\n")
            errors.flush()
            # No console window: one would cover Paltalk, and the relay reads
            # the room from Paltalk's window.
            try:
                self.process = subprocess.Popen(self._command(port), stdin=subprocess.PIPE, stderr=errors,
                                                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            except OSError as error:
                # 9 November: out of memory, Popen raised, this thread died
                # with running still set and the encoder never came back.
                errors.close()
                self.state = "restarting"
                log(f"encoder could not start ({error}); trying again in 10 s")
                time.sleep(10)
                continue
            self.connected_logged = False
            started = time.time()
            threading.Thread(target=self._feed_picture, args=(port, started), daemon=True).start()
            sent = 0
            try:
                while self.running and self.process.poll() is None:
                    due = started + sent / RATE
                    wait = due - time.time()
                    if wait > 0:
                        time.sleep(wait)
                    self.process.stdin.write(self.buffer.read(FRAME).tobytes())
                    sent += FRAME
                    if sent % (RATE * 10) < FRAME:  # every 10 s: is the stream really out?
                        up = self.connected()
                        self.state = "streaming" if up else "not connected"
                        if up and not self.connected_logged:
                            self.connected_logged = True
                            log("encoder connected to the stream server")
                        elif not up and time.time() - started > 30 and sent % (RATE * 60) < FRAME:
                            log("encoder running but NOT connected to the stream server (see programme.log)")
            except (BrokenPipeError, OSError):
                pass
            except Exception as error:  # noqa: BLE001 - never let the feed thread die mid-session
                log(f"encoder feed error: {error!r}")
            try:
                self.process.stdin.close()
                self.process.wait(timeout=5)
            except Exception:  # noqa: BLE001
                self.process.kill()
            errors.close()
            if self.running:
                self.state = "restarting"
                log(f"encoder stopped (code {self.process.returncode}); restarting. Its last words: {last_lines()}")
                time.sleep(2 if time.time() - started > 30 else 10)
        self.state = "off"
