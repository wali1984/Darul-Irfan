"""The stage picture for YouTube and Facebook: the websites' /broadcast page
(the running Latifa, Muraqaba or recitation in the app's theme, 1920x1080),
captured with Edge headless whenever the platform's stage for the Halqah
changes. Between changes nothing runs, which matters on a 2 GB server."""

from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
import threading
import time
import urllib.request
from pathlib import Path

EDGE = Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe")
USER_AGENT = "DarulIrfanRelay/1.0"
REFRESH_EVERY = 600  # re-capture anyway, in case the page's look changed
RETRY_AFTER = 300  # after a failed capture: Edge is the heaviest thing on the server
MIN_COMMIT_MB = 2500  # Edge is never started with less memory than this left


def commit_free_mb() -> int:
    """Memory Windows can still promise (RAM + page file), in MB. On
    9 November repeated Edge captures used it all up mid-Zikr: nothing on the
    server could start, not even the encoder or a remote shell."""
    try:
        import ctypes

        class Status(ctypes.Structure):
            _fields_ = [("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong),
                        ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
                        ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
                        ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
                        ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]

        status = Status()
        status.dwLength = ctypes.sizeof(Status)
        ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status))
        return int(status.ullAvailPageFile / 1_048_576)
    except Exception:  # noqa: BLE001 - not Windows
        return 1 << 20


def log(message: str) -> None:
    print(f"{time.strftime('%H:%M:%S')} [stage] {message}", flush=True)


def stage_signature(platform: str, halqah: str) -> str | None:
    """A fingerprint of the Halqah's live state and stage, or None when the
    platform cannot be reached."""
    request = urllib.request.Request(f"{platform.rstrip('/')}/v1/public/live?ids={halqah}",
                                     headers={"user-agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            data = json.loads(response.read())
    except Exception:  # noqa: BLE001 - the next round retries
        return None
    entry = next((h for h in data.get("halqahs", []) if h.get("id") == halqah), {})
    return hashlib.sha1(json.dumps({"live": entry.get("live"), "stage": entry.get("stage")}, sort_keys=True).encode()).hexdigest()


def capture(url: str, out: Path) -> bool:
    """Renders the page at 1920x1080 into `out` (written atomically)."""
    if not EDGE.exists():
        log("Edge not found; keeping the previous picture")
        return False
    # ignore_cleanup_errors: on 9 November a timed-out Edge still held a file
    # in its profile, the folder's removal raised, and the whole relay died
    # four minutes into the Daily Zikr.
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as profile:
        shot = Path(profile) / "shot.png"
        edge = subprocess.Popen([
            # --do-not-de-elevate: the relay runs elevated, and Edge started
            # elevated in a desktop session relaunches itself un-elevated
            # without these arguments and exits at once (Contabo, 9 November:
            # every capture "produced no picture" in 0.2 s).
            str(EDGE), "--headless=new", "--do-not-de-elevate", "--disable-gpu", "--hide-scrollbars", "--mute-audio",
            "--no-first-run", "--disable-extensions", f"--user-data-dir={profile}",
            "--renderer-process-limit=1", "--disable-background-networking", "--disable-component-update",
            "--disable-sync", "--no-default-browser-check", "--js-flags=--max-old-space-size=128",
            "--window-size=1920,1080", "--virtual-time-budget=8000", f"--screenshot={shot}", url,
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        try:
            edge.wait(timeout=45)
        except subprocess.TimeoutExpired:
            # Edge's helpers too, or they keep the processor and the profile.
            subprocess.run(["taskkill", "/T", "/F", "/PID", str(edge.pid)], capture_output=True)
            log("capture timed out")
            return False
        if not shot.exists() or shot.stat().st_size < 1000:
            log("capture produced no picture")
            return False
        temp = out.with_suffix(".tmp.png")
        temp.write_bytes(shot.read_bytes())
        temp.replace(out)
    return True


class StagePicture:
    def __init__(self, page_url: str, platform: str, halqah: str, out: Path) -> None:
        self.page_url, self.platform, self.halqah, self.out = page_url, platform, halqah, out
        self.signature: str | None = None
        self.captured_at = 0.0
        self.failed_at = 0.0
        self.busy = threading.Lock()

    def refresh(self) -> bytes | None:
        """Captures a new picture when the stage changed; returns its PNG bytes, else None."""
        signature = stage_signature(self.platform, self.halqah)
        due = time.time() - self.captured_at > REFRESH_EVERY
        if signature is None or (signature == self.signature and not due):
            return None
        if time.time() - self.failed_at < RETRY_AFTER:
            return None  # the last picture stays on air
        free = commit_free_mb()
        if free < MIN_COMMIT_MB:
            self.failed_at = time.time()
            log(f"not capturing: only {free} MB of memory left")
            return None
        if not self.busy.acquire(blocking=False):
            return None  # one Edge at a time
        try:
            if capture(self.page_url, self.out):
                self.signature, self.captured_at = signature, time.time()
                log("stage picture updated")
                return self.out.read_bytes()
            self.failed_at = time.time()
            return None
        finally:
            self.busy.release()
