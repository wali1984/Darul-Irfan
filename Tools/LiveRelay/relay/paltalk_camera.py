"""The stage picture as Paltalk's camera.

Paltalk (Qt, Media Foundation) lists only Media Foundation cameras, so an
OBS-style DirectShow virtual camera is invisible to it. The relay server
instead runs "Darul Irfan Stage" (Tools/LiveRelay/stagecam: smourier's
VCamSample, changed to show one picture): a Windows 11 virtual camera made
with MFCreateVirtualCamera. Its media source runs inside Windows' Frame
Server service and draws whatever picture is in

    C:\\ProgramData\\DarulIrfan\\stage.bgra
    (16-byte header "DIST", width, height, 0 - then BGRA rows)

so this module only has to keep that file current: the stage picture YouTube
gets, rewritten whenever it changes. The camera itself lives while
DarulIrfanStage.exe runs (session lifetime); set the event
Local\\DarulIrfanStageCamStop to end it."""

from __future__ import annotations

import ctypes
import io
import os
import struct
import subprocess
import time
from pathlib import Path

import numpy as np

PICTURE = Path(r"C:\ProgramData\DarulIrfan\stage.bgra")
DRIVER = Path(r"C:\ProgramData\DarulIrfan\stagecam\DarulIrfanStage.exe")
WIDTH, HEIGHT = 1280, 720


def log(message: str) -> None:
    print(f"{time.strftime('%H:%M:%S')} [camera] {message}", flush=True)


def write_picture(png: bytes, path: Path = PICTURE) -> None:
    """The PNG, fitted into 1280x720, as the camera's BGRA file (replaced
    whole, so the camera never reads half a picture)."""
    from PIL import Image
    image = Image.open(io.BytesIO(png)).convert("RGB")
    image.thumbnail((WIDTH, HEIGHT))
    frame = np.zeros((HEIGHT, WIDTH, 4), dtype=np.uint8)
    frame[..., :3] = (4, 21, 15)[::-1]  # the stage's dark green, as BGR
    frame[..., 3] = 255
    top, left = (HEIGHT - image.height) // 2, (WIDTH - image.width) // 2
    rgb = np.asarray(image)
    frame[top:top + image.height, left:left + image.width, 0] = rgb[..., 2]
    frame[top:top + image.height, left:left + image.width, 1] = rgb[..., 1]
    frame[top:top + image.height, left:left + image.width, 2] = rgb[..., 0]
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(".tmp")
    temp.write_bytes(struct.pack("<4sIII", b"DIST", WIDTH, HEIGHT, 0) + frame.tobytes())
    os.replace(temp, path)


class PaltalkCamera:
    def __init__(self) -> None:
        self.png: bytes | None = None
        self.process: subprocess.Popen | None = None

    def set_picture(self, png: bytes) -> None:
        if png == self.png:
            return
        try:
            write_picture(png)
            self.png = png
        except Exception as error:  # noqa: BLE001 - the camera keeps the last picture
            log(f"could not write the picture: {error}")

    def start(self) -> None:
        """Brings the camera up (it then shows in Paltalk's camera list)."""
        if self.process and self.process.poll() is None:
            return
        import psutil
        if any((p.info.get("name") or "").lower() == DRIVER.name.lower() for p in psutil.process_iter(["name"])):
            return  # already up (it outlives the relay: stopping it under Paltalk hangs Paltalk)
        if not DRIVER.exists():
            log(f"{DRIVER} is missing")
            return
        self.process = subprocess.Popen([str(DRIVER)], creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        log("Darul Irfan Stage camera started")

    def stop(self) -> None:
        if not (self.process and self.process.poll() is None):
            return
        kernel = ctypes.windll.kernel32
        event = kernel.OpenEventW(0x0002, False, "Local\\DarulIrfanStageCamStop")  # EVENT_MODIFY_STATE
        if event:
            kernel.SetEvent(event)
            kernel.CloseHandle(event)
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.kill()
        log("Darul Irfan Stage camera stopped")
