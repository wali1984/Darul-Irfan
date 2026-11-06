"""The stage picture for YouTube and Facebook: the websites' /broadcast page
(the running Latifa, Muraqaba or recitation in the app's theme, 1920x1080),
captured with Edge headless whenever the platform's stage for the Halqah
changes. Between changes nothing runs, which matters on a 2 GB server."""

from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path

EDGE = Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe")
USER_AGENT = "DarulIrfanRelay/1.0"
REFRESH_EVERY = 600  # re-capture anyway, in case the page's look changed


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
    with tempfile.TemporaryDirectory() as profile:
        shot = Path(profile) / "shot.png"
        try:
            subprocess.run([
                str(EDGE), "--headless=new", "--disable-gpu", "--hide-scrollbars", "--mute-audio",
                "--no-first-run", "--disable-extensions", f"--user-data-dir={profile}",
                "--window-size=1920,1080", "--virtual-time-budget=8000", f"--screenshot={shot}", url,
            ], timeout=60, capture_output=True)
        except subprocess.TimeoutExpired:
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

    def refresh(self) -> bytes | None:
        """Captures a new picture when the stage changed; returns its PNG bytes, else None."""
        signature = stage_signature(self.platform, self.halqah)
        due = time.time() - self.captured_at > REFRESH_EVERY
        if signature is None or (signature == self.signature and not due):
            return None
        if capture(self.page_url, self.out):
            self.signature, self.captured_at = signature, time.time()
            log("stage picture updated")
            return self.out.read_bytes()
        return None
