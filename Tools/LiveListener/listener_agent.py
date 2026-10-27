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

Joining: Paltalk's room search finds a room only while it is open, so the
agent repeats the search every 30 seconds and opens the room's tile the moment
it appears. A listener account never talks; it only listens.

Usage:
  listener_agent.py --once-test 20           # 20 s test to a local file
  listener_agent.py --output srt://... [--backup rtmps://...]
"""

from __future__ import annotations

import argparse
import array
import json
import os
import queue
import shutil
import subprocess
import sys
import threading
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import psutil
import pyaudiowpatch as pyaudio

HERE = Path(__file__).resolve().parent
FRAME = HERE / "daily_zikr_frame.png"
RATE, CHANNELS, CHUNK = 48_000, 2, 1_024
PALTALK = Path(os.environ.get("LOCALAPPDATA", "")) / "Paltalk" / "Paltalk.exe"
SEARCH_EVERY = 30


def log(message: str) -> None:
    print(f"{datetime.now().strftime('%H:%M:%S')} {message}", flush=True)


# MARK: - Room detection

def paltalk_window():
    """Paltalk's main window, or None when Paltalk is not running."""
    from pywinauto import Desktop
    for window in Desktop(backend="uia").windows():
        if (window.element_info.name or "") == "Paltalk":
            return window
    return None


def ensure_paltalk() -> str | None:
    """Starts Paltalk if it is not running. Returns a problem, or None."""
    if any((proc.info.get("name") or "").lower() == "paltalk.exe" for proc in psutil.process_iter(["name"])):
        if paltalk_window():
            return None
        # Closed to the tray: starting it again brings the running copy's
        # window back. It comes to the front, so only at a quiet moment.
        if PALTALK.exists() and seconds_since_input() >= IDLE_BEFORE_SEARCH:
            subprocess.Popen([str(PALTALK)], close_fds=True)
            log("Paltalk window was hidden; reopened it")
        return "Paltalk is running but its window is not available"
    if not PALTALK.exists():
        return "Paltalk is not installed"
    subprocess.Popen([str(PALTALK)], close_fds=True)
    log("Paltalk was not running; started it")
    return "Paltalk was not running (started again)"


IDLE_BEFORE_SEARCH = 20


def seconds_since_input() -> float:
    """How long since anyone touched this PC's keyboard or mouse."""
    import ctypes

    class LastInput(ctypes.Structure):
        _fields_ = [("cbSize", ctypes.c_uint), ("dwTime", ctypes.c_uint)]

    info = LastInput(ctypes.sizeof(LastInput), 0)
    if not ctypes.windll.user32.GetLastInputInfo(ctypes.byref(info)):
        return 0.0
    return ((ctypes.windll.kernel32.GetTickCount() - info.dwTime) & 0xFFFFFFFF) / 1000


def paltalk_has_focus(window) -> bool:
    """True only when the foreground window belongs to Paltalk, so a key
    sent now cannot land in whatever else someone is using on this PC."""
    import ctypes
    from ctypes import wintypes
    user32 = ctypes.windll.user32
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(user32.GetForegroundWindow(), ctypes.byref(pid))
    return pid.value == window.process_id()


def try_join(room: str) -> bool:
    """Searches the room and opens its tile if it is listed (only while the
    room is open). The text goes in through accessibility, not typed keys, so
    nothing lands in another window."""
    window = paltalk_window()
    if window is None:
        return False
    try:
        if window.is_minimized():
            window.restore()
        box = next((e for e in window.descendants(control_type="Edit")
                    if (e.element_info.name or "") == "Search Room"), None)
        if box is None:
            return False
        # The search needs Paltalk in front for one key press. Someone using
        # this PC would lose their window and maybe a keystroke, so wait for
        # a quiet moment, then give their window back.
        if seconds_since_input() < IDLE_BEFORE_SEARCH:
            return False
        import ctypes
        previous = ctypes.windll.user32.GetForegroundWindow()
        box.set_edit_text(room)
        try:
            box.set_focus()
        except Exception:  # noqa: BLE001 - Windows may refuse to change focus
            pass
        if not paltalk_has_focus(window):
            log("Paltalk is not the active window; search left for the next round")
            return False
        box.type_keys("{ENTER}", set_foreground=False)
        if previous:
            ctypes.windll.user32.SetForegroundWindow(previous)
        time.sleep(4)
        wanted = room.strip().lower()
        for tile in window.descendants(control_type="Button"):
            ident = tile.element_info.automation_id or ""
            if ident.endswith("RoomTiles") and (tile.element_info.name or "").strip().lower() == wanted:
                log(f"room listed: {tile.element_info.name}; opening it")
                # Invoke only: a click would move the mouse of whoever is
                # using this PC.
                tile.invoke()
                return True
    except Exception as error:  # noqa: BLE001 - the UI changes under us; try again next round
        log(f"room search failed: {error}")
    return False


ROOM_TOPIC = "naqsh bandia"


def joined_room_title(room: str) -> str | None:
    """The joined room's topic line, or None when not in the room.

    Paltalk shows a joined room as a panel inside its main window
    (ui::rooms::RoomWidget). The room's name is drawn as a picture and is not
    readable, but the topic line under it is: "Hazrat Ameer Abdul Qadeer Awan
    (MZA), Sheikh Silsila Naqsh Bandia Owaisia". So the room counts as joined
    when that panel is open and its topic carries ROOM_TOPIC, or the room's
    name for a room that writes it in its topic."""
    window = paltalk_window()
    if window is None:
        return None
    wanted = {room.lower(), ROOM_TOPIC}
    try:
        panel = next((element for element in window.descendants(control_type="Group")
                      if (element.element_info.automation_id or "").endswith("ui::rooms::RoomWidget")), None)
        if panel is None:
            return None
        for label in panel.descendants(control_type="Text"):
            text = label.element_info.name or ""
            if any(word in text.lower() for word in wanted):
                return text
    except Exception:  # noqa: BLE001 - the UI changes under us; try again next tick
        return None
    return None


def room_panel(window):
    return next((element for element in window.descendants(control_type="Group")
                 if (element.element_info.automation_id or "").endswith("ui::rooms::RoomWidget")), None)


def someone_talking() -> bool:
    """Whether the room shows anyone under Talking Now."""
    window = paltalk_window()
    try:
        panel = room_panel(window) if window else None
        return panel is not None and any(
            (element.element_info.automation_id or "").endswith("ui::rooms::TalkerWidget")
            for element in panel.descendants(control_type="Group"))
    except Exception:  # noqa: BLE001
        return False


def toggle_room_speaker() -> bool:
    """Presses the room's speaker button through accessibility (no mouse,
    no keys). Paltalk does not expose whether the speaker is on, so the
    caller decides from what the loopback hears while someone is talking."""
    window = paltalk_window()
    try:
        panel = room_panel(window) if window else None
        button = next((element for element in panel.descendants(control_type="Button")
                       if (element.element_info.name or "") == "Toggle Speaker"), None) if panel else None
        if button is None:
            return False
        button.invoke()
        return True
    except Exception:  # noqa: BLE001
        return False


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


def env_file(path: Path) -> dict[str, str]:
    """KEY=VALUE lines; blank lines and # comments ignored."""
    values: dict[str, str] = {}
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            key, sep, value = line.strip().partition("=")
            if sep and key and not key.startswith("#"):
                values[key.strip()] = value.strip()
    return values


# MARK: - Encoder

def find_ffmpeg() -> str | None:
    """ffmpeg on this process's PATH, else on the user's saved PATH (a task
    started before ffmpeg was installed has a stale one), else where winget
    puts it."""
    found = shutil.which("ffmpeg")
    if found:
        return found
    if sys.platform == "win32":
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as key:
                saved = os.path.expandvars(winreg.QueryValueEx(key, "Path")[0])
            found = shutil.which("ffmpeg", path=saved)
            if found:
                return found
        except OSError:
            pass
        packages = Path(os.environ.get("LOCALAPPDATA", "")) / "Microsoft" / "WinGet" / "Packages"
        for candidate in sorted(packages.glob("Gyan.FFmpeg*/*/bin/ffmpeg.exe"), reverse=True):
            return str(candidate)
    return None


FFMPEG = find_ffmpeg() or "ffmpeg"


def ensure_frame() -> None:
    """A plain branded frame. Text only, no platform names."""
    if FRAME.exists():
        return
    subprocess.run([
        FFMPEG, "-hide_banner", "-loglevel", "error", "-y",
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
        FFMPEG, "-hide_banner", "-loglevel", "warning", "-nostats", "-y",
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
        self.peak = 0
        # When the loopback last carried sound, so a muted room is noticed.
        self.last_sound = time.time()
        self.reported = time.time()

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
                        self._measure(chunk)
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

    def _measure(self, chunk: bytes) -> None:
        """Logs the loudest sample once a minute, so silence is visible."""
        samples = array.array("h", chunk[: len(chunk) - len(chunk) % 2])
        if samples:
            loudest = max(abs(value) for value in samples[::16])
            self.peak = max(self.peak, loudest)
            if loudest >= 50:
                self.last_sound = time.time()
        if time.time() - self.reported >= 60:
            log(f"audio peak over the last minute: {self.peak} of 32767{' (silent)' if self.peak < 50 else ''}")
            self.peak, self.reported = 0, time.time()

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
    # Each setting can also come from listener.env beside this script, so the
    # stream key and token never sit on a command line others can list.
    settings = env_file(HERE / "listener.env")
    parser.add_argument("--room", default=settings.get("ROOM", "oursheikh"))
    parser.add_argument("--output", default=settings.get("OUTPUT"), help="srt:// (hub) or rtmps:// (direct) destination")
    parser.add_argument("--heartbeat-url", default=settings.get("HEARTBEAT_URL"))
    parser.add_argument("--heartbeat-token", default=settings.get("LISTENER_TOKEN"))
    parser.add_argument("--listener-id", default=settings.get("LISTENER_ID", "listener-a"))
    parser.add_argument("--input-id", default=settings.get("INPUT_ID"), help="the Cloudflare Stream live input this listener feeds")
    parser.add_argument("--once-test", type=int, metavar="SECONDS",
                        help="stream SECONDS of whatever is playing to a local test file, then stop")
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    if find_ffmpeg() is None:
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
    last_search = 0.0
    # A room whose speaker is off plays nothing, so nothing is captured.
    # Someone under Talking Now with silence on the loopback means the
    # speaker is off: press it, and press again if that made it worse.
    talker_since: float | None = None
    last_toggle = 0.0
    toggles_without_sound = 0
    try:
        while True:
            problem = ensure_paltalk()
            title = joined_room_title(args.room) if problem is None else None
            if title is None and problem is None and time.time() - last_search >= SEARCH_EVERY:
                last_search = time.time()
                if try_join(args.room):
                    time.sleep(5)
                    title = joined_room_title(args.room)
            if title and encoder is None:
                log(f"in the room ({title}); going live")
                encoder = Encoder(audio, args.output)
                encoder.start()
            elif not title and encoder is not None:
                log("room closed or left; stopping")
                encoder.stop()
                encoder = None
            if title and encoder is not None:
                now = time.time()
                if someone_talking():
                    talker_since = talker_since or now
                    if now - encoder.last_sound < 45:
                        toggles_without_sound = 0
                    elif now - talker_since >= 45 and now - last_toggle >= 45 and toggle_room_speaker():
                        last_toggle = now
                        toggles_without_sound += 1
                        log("someone is talking but nothing is heard; pressed the room speaker")
                else:
                    talker_since = None
                if toggles_without_sound >= 3:
                    problem = "Someone is talking in the room but no sound reaches the stream"
            if title and encoder is not None and encoder.process and encoder.process.poll() is not None:
                problem = "In the room but the stream keeps stopping"
            heartbeat(args.heartbeat_url, args.heartbeat_token,
                      {"listener": args.listener_id, "inRoom": bool(title), "streaming": encoder is not None,
                       "input": args.input_id, "problem": problem})
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
