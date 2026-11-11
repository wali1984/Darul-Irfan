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
import urllib.parse
import urllib.request
from pathlib import Path

EDGE = Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe")
USER_AGENT = "DarulIrfanRelay/1.0"
REFRESH_EVERY = 600  # re-capture anyway, in case the page's look changed
RETRY_AFTER = 300  # after a failed capture: Edge is the heaviest thing on the server
MIN_COMMIT_MB = 2500  # Edge is never started with less memory than this left

# Every stage's picture drawn ahead of time (/broadcast?stage=<id>), so the
# stream's picture changes the moment the stage does: a capture after the
# change took 5-10 s (owner, 11 November: "more than 5 seconds delay"). "none"
# is the screen before anything is heard.
READY_STAGES = ["none", "waiting", "bayan", "tasbih", "istighfar", "shahadah", "taawwudh", "basmalah",
                "latifa-1", "latifa-2", "latifa-3", "latifa-4", "latifa-5", "latifa-6", "latifa-7", "raabta",
                "ahadiyat", "maiyyat", "aqrabiyyat", "sair-kaaba", "rauza-athar", "masjid-nabawi", "shajra", "dua",
                "bayan-after"]
# The Shajra's lines rise through its card on the websites (3.5 s a line, 14
# lines, after a second); a still picture showed only its first lines for
# good (11 November: "Shajra didn't complete"). The stream steps through
# these frames instead, the last held until the next stage.
SHAJRA_FRAMES = 8
SHAJRA_SECONDS = 1 + 14 * 3.5
READY_MAX_AGE = 12 * 3600  # a ready picture older than this is drawn again (Hazrat ji's picture changes daily)


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


def with_query(url: str, **params: str) -> str:
    parts = urllib.parse.urlsplit(url)
    query = urllib.parse.parse_qsl(parts.query) + list(params.items())
    return urllib.parse.urlunsplit(parts._replace(query=urllib.parse.urlencode(query)))


def shajra_frame(elapsed: float) -> int:
    """The Shajra frame for `elapsed` seconds after the Shajra began."""
    return max(0, min(SHAJRA_FRAMES - 1, int(elapsed / SHAJRA_SECONDS * (SHAJRA_FRAMES - 1) + 0.5)))


class StagePicture:
    def __init__(self, page_url: str, platform: str, halqah: str, out: Path) -> None:
        self.page_url, self.platform, self.halqah, self.out = page_url, platform, halqah, out
        self.signature: str | None = None
        self.captured_at = 0.0
        self.failed_at = 0.0
        self.busy = threading.Lock()
        self.ready_dir = out.parent / "stage_ready"
        self.ready_cache: dict[str, tuple[float, bytes]] = {}
        self.preparing = False

    def _ready_items(self) -> list[tuple[str, dict]]:
        items = []
        for stage in READY_STAGES:
            if stage == "shajra":
                items += [(f"shajra-{k}", {"stage": stage, "roll": f"{k / (SHAJRA_FRAMES - 1):.3f}"}) for k in range(SHAJRA_FRAMES)]
            else:
                items.append((stage, {"stage": stage}))
        return items

    def ready(self, stage: str | None, elapsed: float = 0.0) -> bytes | None:
        """The picture drawn ahead of time for `stage` (None: before anything
        is heard; the Shajra by `elapsed` seconds since it began), or None."""
        name = "none" if stage is None else (f"shajra-{shajra_frame(elapsed)}" if stage == "shajra" else stage)
        path = self.ready_dir / f"{name}.png"
        try:
            mtime = path.stat().st_mtime
        except OSError:
            return None
        cached = self.ready_cache.get(name)
        if cached and cached[0] == mtime:
            return cached[1]
        png = path.read_bytes()
        self.ready_cache[name] = (mtime, png)
        return png

    def prepare(self) -> None:
        """Draws every stage's picture that is missing or old, one Edge at a
        time, in the Zikr's order (the opening first). Run on its own thread
        at the relay's start and as each session begins; a capture that
        fails or finds too little memory leaves the rest to the next round."""
        if self.preparing:
            return
        self.preparing = True
        try:
            self.ready_dir.mkdir(exist_ok=True)
            drawn = 0
            for name, params in self._ready_items():
                path = self.ready_dir / f"{name}.png"
                if path.exists() and time.time() - path.stat().st_mtime < READY_MAX_AGE:
                    continue
                if commit_free_mb() < MIN_COMMIT_MB:
                    log("ready pictures: too little memory; the rest next time")
                    return
                with self.busy:  # one Edge at a time, the live capture included
                    if not capture(with_query(self.page_url, **params), path):
                        log(f"ready picture {name} not drawn; the rest next time")
                        return
                drawn += 1
            if drawn:
                log(f"{drawn} ready stage pictures drawn")
        finally:
            self.preparing = False

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
