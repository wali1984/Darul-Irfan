"""Darul Irfan live relay (Windows). Joins the Paltalk room with its own
account and carries the programme both ways through the staging Worker:

  Paltalk room  -> speaker cable -> SFU track "paltalk-<id>" -> app listeners
  app broadcast -> SFU -> mic cable -> Paltalk room          (not LISTEN_ONLY)
  room cues     -> the platform's cue list (app, websites)
  app cues      -> room chat                                 (posting: not LISTEN_ONLY)
  programme     -> ffmpeg -> YouTube                         (when YOUTUBE_URL is set)

Only the relay holding the Worker's lease acts; a standby relay waits.
LISTEN_ONLY=1 never touches the room's mic or chat (used in Our Sheikh).
Settings: relay.env beside this file (see relay.env.example).
"""

from __future__ import annotations

import asyncio
import os
import queue
import re
import sys
import threading
import time
import uuid
from pathlib import Path

import numpy as np
import psutil

HERE = Path(__file__).resolve().parent
DUA_FILE = HERE / "dua_given.txt"  # when the last dua was given, kept across restarts
sys.path.insert(0, str(HERE))

import paltalk_ui as pt  # noqa: E402
from audio_picker import ORDER, ahead  # noqa: E402
from audio_io import BufferTrack, DeviceInput, DeviceOutput, PcmBuffer, drain  # noqa: E402
from cues import PlatformCues, is_dua, stage_id  # noqa: E402
from live_client import ApiError, Worker, publish, pull  # noqa: E402
from programme import Programme  # noqa: E402
from stage_picture import StagePicture  # noqa: E402


LEAVE_AFTER = 20.0   # seconds of a clear "no room open" before the relay has left the room
SPEAKER_TRIES = 2    # unconfirmed speaker presses before the relay stops pressing (then: one rejoin)
REJOIN_AFTER = 600.0  # seconds in a room whose speaker cannot be switched on before leaving and rejoining it
REJOIN_EVERY = 1200.0  # at most one such rejoin this often
START_VOICE = 5.0    # seconds of sound in the room that start the platform's Zikr
DUA_AFTER = {"masjid-nabawi", "shajra"}  # stages after which members' "aameen" means the dua
AMEEN = re.compile(r"\b(aa?mee?n|ameen|amin|aameen)\b|آمین|آمِین|امین", re.IGNORECASE)
# Opening recitations come from the room's sound only: a host's "Astaghfirullah"
# during the dua is devotion, not a cue (6 November).
OPENING_STAGES = {"tasbih", "istighfar", "shahadah", "taawwudh", "basmalah"}


def typed_stage(text: str) -> str | None:
    """A host's typed cue: a Latifa or a Muraqaba, never a recitation."""
    stage = stage_id(text)
    return None if stage in OPENING_STAGES else stage


def log(message: str) -> None:
    print(f"{time.strftime('%H:%M:%S')} {message}", flush=True)


def settings() -> dict[str, str]:
    """relay.env, then relay.override.env on top of it when present (tests:
    delete the override and the relay is back on its production settings)."""
    values = dict(os.environ)
    for name in ("relay.env", "relay.override.env"):
        env = HERE / name
        if env.exists():
            for line in env.read_text(encoding="utf-8").splitlines():
                key, sep, value = line.strip().partition("=")
                if sep and key and not key.startswith("#"):
                    values[key.strip()] = value.strip()
    return values


def _get_json(url: str) -> dict:
    import json
    import urllib.request
    request = urllib.request.Request(url, headers={"user-agent": "DarulIrfanRelay/1.0"})
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


class Relay:
    def __init__(self, cfg: dict[str, str]) -> None:
        self.cfg = cfg
        self.id = cfg.get("RELAY_ID", "relay-a")
        self.worker = Worker(cfg["WORKER_URL"], cfg["RELAY_KEY"])
        self.listen_only = cfg.get("LISTEN_ONLY", "1") != "0"
        self.room = cfg.get("PALTALK_ROOM", "")
        self.markers = [m.strip() for m in cfg.get("ROOM_MARKERS", self.room).split(",") if m.strip()]
        self.cue_hosts = {h.strip().lower() for h in cfg.get("CUE_HOSTS", "").split(",") if h.strip()}
        self.capture_name = cfg.get("ROOM_CAPTURE_DEVICE", "CABLE Output")
        self.mic_name = cfg.get("MIC_DEVICE", "Hi-Fi Cable Input")
        self.track_name = f"paltalk-{self.id}"

        self.lease = False
        self.state: dict = {}
        self.joined: str | None = None
        self.problem: str | None = None
        self.mode = "idle"
        self.mic_held = False

        self.room_audio = PcmBuffer()  # what the room sounds like
        self.app_audio = PcmBuffer()   # the app broadcast, into Paltalk's mic
        self.capture: DeviceInput | None = None
        self.mic_out: DeviceOutput | None = None
        self.pub_pc = None
        self.pub_session: str | None = None
        self.pull_pc = None
        self.pull_key: str | None = None
        self.pull_task: asyncio.Task | None = None
        self.posted_seq = 0
        self.chat = pt.MessageFollower()
        self.last_join_try = 0.0
        self.join_tries = 0
        self.not_ready_since: float | None = None
        self.last_start_try = 0.0
        self.last_cue_from_room = 0.0
        self.left_room_at: float | None = None
        # The room as last read: in / out / closed / unknown (paltalk_ui.room_status).
        self.room_status = "unknown"
        self.in_streak = 0
        self.walk_seconds = 0.0
        self.joined_at = 0.0
        self.out_since: float | None = None
        self.unknown_since: float | None = None
        self.first_closed_at: float | None = None
        self.close_dua_sent = False
        # The room's speaker: True on, False muted, None not readable.
        self.speaker_state: bool | None = None
        self.speaker_due = 0.0
        self.speaker_fixed_at = 0.0
        self.speaker_tries = 0      # unconfirmed presses in a row
        self.rejoined_at = 0.0
        self.voice_since: float | None = None
        self.cues_done: set[str] = set()
        self.ameens: list[tuple[float, str]] = []
        self.dua_shown = False
        self.health_at = 0.0
        self.prompt_checked_at = 0.0
        self.lease_failing_since: float | None = None
        # PUBLISH_AUDIO=0: tests in other rooms never reach listeners.
        self.publish_audio = cfg.get("PUBLISH_AUDIO", "1") != "0"
        try:
            self.dua_at = float(DUA_FILE.read_text().strip())
        except (OSError, ValueError):
            self.dua_at = 0.0
        # A restart in a room still open after its dua must not start
        # another Zikr; a dua older than two hours belongs to an earlier one.
        self.dua_given = time.time() - self.dua_at < 7200
        self.platform_live = False  # a Zikr this relay started on the platform
        outputs = [cfg.get("YOUTUBE_URL", ""), cfg.get("FACEBOOK_URL", "")]
        self.programme = Programme(outputs, HERE / "daily_zikr_frame.png") if any(outputs) else None
        platform = cfg.get("PLATFORM_URL", "https://darul-irfan-platform.wajidmahmoodali1984-e23.workers.dev")
        self.platform = platform
        self.halqah = cfg.get("HALQAH_ID", "our-sheikh")
        # Paltalk's camera: the "Darul Irfan Stage" virtual camera shows the
        # same stage picture YouTube gets (paltalk_camera.py).
        self.camera = None
        if cfg.get("PALTALK_CAMERA", "0") == "1":  # not proven yet: other members got no picture
            from paltalk_camera import PaltalkCamera
            self.camera = PaltalkCamera()
        self.picture = StagePicture(cfg.get("BROADCAST_PAGE", f"https://oursheikh.wajidali.us/broadcast?halqah={self.halqah}"),
                                    platform, self.halqah, HERE / "stage.png")
        token = cfg.get("PLATFORM_CUE_TOKEN", "")
        # PLATFORM_TEST=1 (simulations): the platform's Test Zikr - admins
        # only, no notifications.
        self.platform_cues = PlatformCues(platform, self.halqah, token, test=cfg.get("PLATFORM_TEST") == "1") if token else None
        # The audio picker names the stage from the room's sound; typed cues
        # are its backup (owner, 2026-11-06).
        self.platform_is_live = False
        self.platform_stage: str | None = None
        self.stage_set_at = 0.0     # when this relay last set the stage itself
        self.heard_at: dict[str, float] = {}  # stage -> when the picker gave it
        self.loop: asyncio.AbstractEventLoop | None = None
        self.picker = None
        self.picker_audio: queue.SimpleQueue = queue.SimpleQueue()
        if self.platform_cues and cfg.get("AUDIO_PICKER", "1") != "0":
            from audio_picker import Picker  # loads Whisper on the first call
            self.picker = Picker(self._picked, lambda: self.platform_stage, model_name=cfg.get("PICKER_MODEL", "base"))
            threading.Thread(target=self._feed_picker, daemon=True).start()

    # MARK: - Worker

    async def keep_lease(self) -> None:
        """The Worker's lease (20 s) says which relay acts. A failed call is
        a network blip, not a lost lease: the relay keeps acting for 15 s of
        failures (the lease itself lasts 20 s) instead of dropping the
        listeners' sound at the first one."""
        while True:
            try:
                result = await self.worker.call("POST", "/api/lease", {"relayId": self.id})
                if result["granted"] != self.lease:
                    log("holding the lease" if result["granted"] else f"standby: lease held by {result.get('holder')}")
                self.lease = result["granted"]
                self.lease_failing_since = None
            except Exception as error:  # noqa: BLE001 - the network; next round
                self.lease_failing_since = self.lease_failing_since or time.time()
                if self.lease and time.time() - self.lease_failing_since > 15:
                    log(f"lease lost: the Worker has not answered for 15 s ({error})")
                    self.lease = False
                elif self.lease:
                    log(f"lease call failed (keeping it for now): {error}")
            await asyncio.sleep(5)

    async def follow_state(self) -> None:
        while True:
            try:
                self.state = await self.worker.call("GET", "/api/state")
            except Exception as error:  # noqa: BLE001
                log(f"state read failed: {error}")
            await asyncio.sleep(1)

    async def report(self) -> None:
        while True:
            if self.lease:
                sound_ago = time.time() - self.room_audio.last_sound
                status = {
                    "mode": self.mode,
                    "listenOnly": self.listen_only,
                    "paltalk": await asyncio.to_thread(pt.running),
                    "joined": bool(self.joined),
                    "room": self.joined,
                    "roomStatus": self.room_status,
                    "speaker": {True: "on", False: "off", None: "unknown"}[self.speaker_state],
                    "lastSoundSecondsAgo": None if sound_ago > 1e8 else int(sound_ago),
                    "platformLive": self.platform_is_live,
                    "stage": self.platform_stage,
                    "duaShown": self.dua_shown,
                    "cpu": psutil.cpu_percent(),
                    "micHeld": self.mic_held,
                    "roomPeak": self.room_audio.take_peak(),
                    "appPeak": self.app_audio.take_peak(),
                    "youtube": self.programme.state if self.programme else "not configured",
                    "freeMB": int(psutil.virtual_memory().available / 1_048_576),
                    "problem": self.problem,
                }
                try:
                    await self.worker.call("POST", "/api/relay-status", {"relayId": self.id, "status": status})
                except Exception:  # noqa: BLE001
                    pass
            await asyncio.sleep(3)

    # MARK: - Paltalk room

    async def watch_room(self) -> None:
        """One read of Paltalk per round, and a steady idea of the room.

        6 November: misreads of Paltalk's window were taken for leaving the
        room; the relay reopened a room it was in (each reopen toggled the
        speaker) and, a minute later, sent the dua in the middle of the Zikr.
        Now a read that fails is "unknown" and changes nothing, leaving takes
        LEAVE_AFTER seconds of a clear "no room open", and only Paltalk's own
        "this room is not open" - seen twice, a join attempt apart - is the
        room closing. The room's speaker is read from its icon and switched
        on only when it is seen off, and kept only when seen on after."""
        while True:
            problem = await asyncio.to_thread(pt.ensure_running)
            view = await asyncio.to_thread(pt.look) if not problem else None
            now = time.time()
            if view is not None:
                self.walk_seconds = view.seconds
            if view is not None and view.ok:
                await asyncio.to_thread(pt.close_popups_in, view)
            if view is None:
                status, detail = "unknown", problem or "Paltalk is not running"
            else:
                status, detail = await asyncio.to_thread(pt.room_status, view, self.markers, self.room)
            if status != self.room_status:
                log(f"[room] {status}: {detail}")
            self.room_status = status

            self.in_streak = self.in_streak + 1 if status == "in" else 0
            if status == "in":
                self.out_since = self.unknown_since = None
                # Two reads in a row: joining a closed room shows the room for
                # a moment before Paltalk's "not open" (6 November 12:52).
                if not self.joined and self.in_streak >= 2:
                    self.first_closed_at = None
                    self._entered(detail, view)
            elif status == "closed":
                self.unknown_since = None
                if self.joined:
                    self._left("Paltalk says the room is not open")
                await self._room_closed(now)
            elif status == "out":
                self.unknown_since = None
                if self.joined:
                    self.out_since = self.out_since or now
                    if now - self.out_since >= LEAVE_AFTER:
                        self._left(f"no room open for {LEAVE_AFTER:.0f} s")
            else:
                self.unknown_since = self.unknown_since or now
                if now - self.unknown_since > 120:
                    problem = problem or f"cannot read Paltalk's window for 2 minutes ({detail})"
                if detail.startswith("the room's tab is open") and now - self.unknown_since > 30 \
                        and now - self.last_join_try > 120 and self.lease:
                    # Joined, but another page is in front: bring the room back.
                    self.last_join_try = now
                    await asyncio.to_thread(pt.try_join, self.room, self.cfg.get("PALTALK_ROOM_LINK") or None)

            if not self.joined and status in ("out", "closed") and not problem:
                if view is not None and pt.signed_in_view(view):
                    self.not_ready_since = None
                    if now - self.prompt_checked_at > 30:  # its own walk: not every round
                        self.prompt_checked_at = now
                        await asyncio.to_thread(pt.dismiss_prompt)
                    # A closed room's link opens nothing: after three tries,
                    # look every two minutes (a Zikr's first minutes matter more
                    # than the moment it takes to close Paltalk's notice).
                    wait = 60 if self.join_tries < 3 else 120
                    if self.lease and self.room and now - self.last_join_try > wait:
                        self.last_join_try = now
                        self.join_tries += 1
                        await asyncio.to_thread(pt.try_join, self.room, self.cfg.get("PALTALK_ROOM_LINK") or None)
                else:
                    # Stuck on the loading or sign-in screen: say so, and
                    # after ten minutes start Paltalk over once - never while
                    # someone is on Remote Desktop, who may be signing in.
                    self.not_ready_since = self.not_ready_since or now
                    problem = "Paltalk is not signed in"
                    if await asyncio.to_thread(pt.login_form):
                        # Signed out: a restart cannot sign in again (and each
                        # one risks Paltalk hanging on its splash). Someone
                        # must sign in on the server; say so, leave it alone.
                        problem = "Paltalk is signed out: sign in as the relay account on the server"
                        self.not_ready_since = now
                    elif pt.remote_desktop_connected():
                        self.not_ready_since = now
                    elif now - self.not_ready_since > 600:
                        await asyncio.to_thread(pt.restart)
                        self.not_ready_since = now

            # Sound in the room: what starts a Zikr, and the health line.
            if self.joined and now - self.room_audio.last_sound < 3:
                self.voice_since = self.voice_since or now
            else:
                self.voice_since = None

            if self.joined and view is not None and view.ok:
                if now >= self.speaker_due:
                    await self._check_speaker(view)
                if self.lease:
                    await self._read_chat(view)
            if self.joined and self.speaker_tries >= SPEAKER_TRIES and self.speaker_state is not True:
                problem = problem or "the room's speaker could not be switched on (Paltalk may not have drawn the room)"
                await self._recover_room(now)
            await self._track_on_air()
            self.problem = problem
            self._health(now)
            await asyncio.sleep(2)

    def _entered(self, detail: str, view) -> None:  # noqa: ANN001
        log(f"in the room: {detail}")
        self.joined = detail
        self.joined_at = time.time()
        self.join_tries = 0
        self.out_since = None
        self.chat = pt.MessageFollower()
        self.speaker_due = time.time() + 4  # Paltalk joins rooms muted: look at once
        self.speaker_state = None
        self.speaker_tries = 0
        if view is not None:
            hide = view.first(name="Hide Video Area", kind="Button")
            if hide is not None:
                try:
                    hide.invoke()
                    log("video area hidden")
                except Exception:  # noqa: BLE001
                    pass

    def _left(self, why: str) -> None:
        log(f"not in the room ({why})")
        self.joined = None
        self.left_room_at = time.time()
        self.out_since = None
        self.speaker_state = None

    async def _check_speaker(self, view) -> None:  # noqa: ANN001
        """The room's speaker, from its icon. Off: press it once, look again,
        and keep the press only if the icon turned green; anything else is
        put back as it was - a guess is never left in place. After
        SPEAKER_TRIES unconfirmed presses the relay stops pressing (on
        6 November it pressed twice a minute for an hour in a room Paltalk
        had not drawn): the next rung is a rejoin, in _recover_room."""
        on = await asyncio.to_thread(pt.speaker_on, view)
        now = time.time()
        self.speaker_due = now + 15
        if on is not self.speaker_state:
            log(f"[speaker] {'on' if on else 'off' if on is False else 'cannot be read (is the screen drawn?)'}")
        self.speaker_state = on
        if on is True:
            self.speaker_tries = 0
            return
        if on is None or now - self.speaker_fixed_at < 90 or self.speaker_tries >= SPEAKER_TRIES:
            return
        self.speaker_tries += 1
        self.speaker_fixed_at = now
        icon = pt.speaker_icon(view)
        if not await asyncio.to_thread(pt.press_speaker, view):
            log("[speaker] off, and the Toggle Speaker button was not found")
            return
        # A slow server can take seconds to redraw: watch the icon for 15 s.
        if await self._icon_becomes(icon, True, 15):
            self.speaker_state = True
            log("[speaker] switched on (Paltalk had the room muted)")
            return
        await asyncio.to_thread(pt.press_speaker, view)
        back = await self._icon_becomes(icon, False, 15)
        log(f"[speaker] pressed, but the icon did not turn on in 15 s; pressed again to leave it as it was"
            f"{'' if back else ' (and it did not show off either: check the server)'}"
            f"{'; no more presses - a rejoin follows' if self.speaker_tries >= SPEAKER_TRIES else ''}")
        self.speaker_state = None if not back else False

    async def _recover_room(self, now: float) -> None:
        """The speaker could not be switched on after SPEAKER_TRIES presses:
        after REJOIN_AFTER seconds in the room, leave it and join again (a
        half-drawn room comes back whole), at most once in REJOIN_EVERY
        seconds - and never while a Zikr is live and the room is heard."""
        if now - self.joined_at < REJOIN_AFTER or now - self.rejoined_at < REJOIN_EVERY:
            return
        if self.platform_is_live and now - self.room_audio.last_sound < 60:
            return  # listeners are hearing the room: leave it alone
        self.rejoined_at = now
        left = await asyncio.to_thread(pt.leave_room, pt.look(), self.room)
        log(f"[speaker] rejoining the room ({'left it' if left else 'could not find its close button'})")
        if left:
            self._left("rejoining: the speaker could not be switched on")
            self.last_join_try = now - 60  # join on the next round

    async def _icon_becomes(self, icon, wanted: bool, seconds: float) -> bool:  # noqa: ANN001
        end = time.time() + seconds
        while time.time() < end:
            await asyncio.sleep(1.5)
            if await asyncio.to_thread(pt.icon_on, icon) is wanted:
                return True
        return False

    async def _read_chat(self, view) -> None:  # noqa: ANN001
        """The room's chat: hosts' typed cues (the backup to the sound), a
        host's "Dua", and the members' "aameen" that means the dua is on."""
        me = self.cfg.get("PALTALK_USER", "").lower()
        fresh = [(s, t) for s, t in await asyncio.to_thread(self.chat.new, view) if s.lower() != me]
        now = time.time()
        for sender, text in fresh:
            if AMEEN.search(text):
                self.ameens.append((now, sender.lower()))
        self.ameens = [(t, s) for t, s in self.ameens if now - t < 120]
        cues = [(s, t) for s, t in fresh if s.lower() in self.cue_hosts and (is_dua(t) or typed_stage(t))]
        if len(cues) > 2:
            # The chat jumped and old lines read as new: hosts call one cue
            # at a time, so only the newest counts.
            log(f"{len(cues)} cues at once: only the newest is current")
            cues = cues[-1:]
        for sender, text in cues:
            if is_dua(text):
                await self._show_dua(f"{sender} wrote it")
                continue
            stage = typed_stage(text)
            if stage in self.cues_done:
                continue  # the same cue again (a redraw, or a repeat)
            self.cues_done.add(stage)
            log(f"cue from {sender}: {text[:60]!r} -> {stage}")
            asyncio.ensure_future(self._typed_cue(stage, text))
        for sender, text in fresh:
            if sender.lower() in self.cue_hosts and not (is_dua(text) or typed_stage(text)):
                log(f"host {sender}: {text[:60]!r} (not a cue)")
        senders = {s for _, s in self.ameens}
        if (not self.dua_shown and self.platform_is_live and self.platform_stage in DUA_AFTER
                and len(self.ameens) >= 3 and len(senders) >= 2):
            await self._show_dua(f"{len(self.ameens)} aameen from {len(senders)} members after {self.platform_stage}")

    async def _show_dua(self, why: str) -> None:
        """The dua has begun: the stage shows it (a "dua" cue). The session is
        not ended here - it ends five minutes after the room closes - so app
        listeners hear the whole dua."""
        if self.dua_shown or not self.platform_is_live:
            return
        self.dua_shown = True
        log(f"dua begins ({why})")
        await self._send_cue("dua", "dua")

    async def _room_closed(self, now: float) -> None:
        """Paltalk says the room is not open. Seen twice, a join attempt
        apart, while a Zikr is live: the Zikr is over - send the dua (the
        platform ends the session five minutes later)."""
        if self.first_closed_at is None:
            self.first_closed_at = now
            return
        if now - self.first_closed_at < 45 or self.close_dua_sent:
            return
        if self.lease and self.platform_cues and self.mode != "app" and (self.platform_is_live or self.platform_live):
            self.close_dua_sent = True
            await self._dua("the room closed")

    async def _track_on_air(self) -> None:
        """The platform's Zikr starts when the relay is in the room and the
        room has been heard for START_VOICE seconds (owner: the mic opening
        is the start; the tasbih may follow seconds or minutes later) - not
        merely when the room opens, because Our Sheikh can sit open and
        silent for hours before the Tahajjud. A host's cue also starts it
        (see _send_cue). After a dua in a room left open, a new Zikr needs
        20 minutes and longer sound."""
        if not (self.joined and self.lease and self.platform_cues) or self.mode == "app":
            return
        if self.platform_is_live or self.platform_live:
            return
        heard = time.time() - self.voice_since if self.voice_since else 0.0
        if self.dua_given:
            if time.time() - self.dua_at < 1200 or heard < 10:
                return
            log("someone took the mic in the open room: a new Zikr")
            self._clear_dua()
        elif heard < START_VOICE:
            return
        await self._start_now(f"{heard:.0f} s of sound in the room")

    async def _start_now(self, why: str) -> None:
        """Starts the Halqah's Zikr on the platform (or finds it live)."""
        if not self.platform_cues or time.time() - self.last_start_try < 30:
            return
        self.last_start_try = time.time()
        title = "Tahajjud Zikr" if (time.gmtime().tm_hour + 5) % 24 < 7 else "Daily Zikr"
        status, body = await asyncio.to_thread(self.platform_cues.start, title)
        if status in (200, 201):
            self.platform_live = True
            log(f"platform Zikr {'started' if status == 201 else 'already live'} ({why}): {title}"
                f"{' (test)' if self.platform_cues.test else ''}")
        else:
            log(f"platform Zikr not started ({status}): {body}")

    async def _dua(self, why: str) -> None:
        if not self.platform_cues:
            return
        status, body = await asyncio.to_thread(self.platform_cues.dua)
        log(f"dua on the platform ({why}): {status} {body}")
        if status in (200, 201, 409):
            self.platform_live = False
            self.dua_given = True
            self.dua_at = time.time()
            try:
                DUA_FILE.write_text(str(self.dua_at))
            except OSError:
                pass

    def _clear_dua(self) -> None:
        self.dua_given = False
        self.dua_at = 0.0
        DUA_FILE.unlink(missing_ok=True)

    def _new_session(self, live: bool) -> None:
        """The platform's Zikr began or ended: forget the last one's cues."""
        self.cues_done.clear()
        self.ameens.clear()
        self.dua_shown = False
        self.close_dua_sent = False
        self.first_closed_at = None
        if not live:
            self.platform_live = False
        if self.picker:
            self.picker.reset()

    def _health(self, now: float) -> None:
        """One line a minute while in the room or while a Zikr is live: what
        a post-mortem needs."""
        if now - self.health_at < 60 or not (self.joined or self.platform_is_live):
            return
        self.health_at = now
        sound = now - self.room_audio.last_sound
        speaker = {True: "on", False: "OFF", None: "unknown"}[self.speaker_state]
        log(f"[health] room={self.room_status} speaker={speaker} last-sound={'never' if sound > 1e8 else f'{sound:.0f}s'} "
            f"publishing={'yes' if self.pub_pc is not None else 'no'} platform={'live' if self.platform_is_live else 'off'} "
            f"stage={self.platform_stage} dua={'shown' if self.dua_shown else 'no'} "
            f"youtube={self.programme.state if self.programme else '-'} cpu={psutil.cpu_percent():.0f}% "
            f"read={self.walk_seconds:.1f}s problem={self.problem or '-'}")

    async def _send_cue(self, stage: str, text: str) -> None:
        """To the platform's cue list (the one source of truth), keeping one
        id across retries; also to the staging test page's log."""
        try:
            await self.worker.call("POST", "/api/stage", {"stage": text[:80], "origin": "paltalk"})
        except Exception:  # noqa: BLE001 - the staging log is only for the test page
            pass
        if not self.platform_cues:
            return
        if stage != "dua" and self.dua_shown:
            if not text.startswith("heard:"):
                # A host's typed cue after the dua was shown: the dua was not
                # the end after all - the host's word wins.
                log(f"cue {stage} after the dua was shown: the host's cue wins")
                self.dua_shown = False
            else:
                log(f"[picker] {stage} ignored: the dua is on")
                return
        cue_id = str(uuid.uuid4())
        self.last_cue_from_room = time.time()
        for attempt in range(6):
            status, why = await asyncio.to_thread(self.platform_cues.post, stage, cue_id)
            if status in (200, 201):
                log(f"cue {stage} on the platform")
                return
            if status == 409 and stage == "dua":
                log("dua cue: no Zikr live on the platform")
                return
            if status == 409 and attempt == 0 and time.time() - self.dua_at > 600:
                # A host's cue means Zikr is on, though the platform has none
                # live (the room opened early, or stayed open after a dua).
                log(f"cue {stage} with no Zikr on the platform: starting one")
                self._clear_dua()
                self.platform_live = False
                self.last_start_try = 0.0
                await self._start_now(f"a cue ({stage})")
                continue
            if status in (401, 404, 409):
                log(f"cue {stage} refused by the platform: {why}")
                return
            await asyncio.sleep(5)
        log(f"cue {stage} not delivered: {why}")

    # MARK: - Room audio -> SFU

    async def publish_room(self) -> None:
        """The room's sound to the SFU while a Zikr is live (or being
        started) on the platform. Before that the room can sit open for
        hours, and the websites would offer a Join that leads nowhere."""
        while True:
            # Without the platform (sound-only tests) the room is sent whenever the relay is in it.
            live = (self.platform_is_live or self.platform_live) if self.platform_cues else True
            want = self.publish_audio and self.lease and bool(self.joined) and self.mode != "app" and live
            if want and self.pub_pc is None:
                try:
                    self.pub_pc, self.pub_session = await publish(self.worker, BufferTrack(self.room_audio), self.track_name)
                    log("publishing the room's audio")
                except Exception as error:  # noqa: BLE001
                    log(f"publish failed: {error}")
                    self.pub_pc = None
            if self.pub_pc is not None and (not want or self.pub_pc.connectionState in ("failed", "closed")):
                if self.pub_session:
                    try:
                        await self.worker.call("POST", "/api/source", {"source": "paltalk", "sessionId": self.pub_session, "relayId": self.id, "live": False})
                    except Exception:  # noqa: BLE001
                        pass
                await self.pub_pc.close()
                self.pub_pc, self.pub_session = None, None
                log("stopped publishing the room's audio")
            if self.pub_pc is not None:
                try:
                    await self.worker.call("POST", "/api/source", {"source": "paltalk", "sessionId": self.pub_session,
                                                                   "trackName": self.track_name, "relayId": self.id, "by": self.id})
                except ApiError as error:
                    log(f"source heartbeat refused: {error}")
                except Exception:  # noqa: BLE001
                    pass
            await asyncio.sleep(3)

    # MARK: - App broadcast -> Paltalk mic

    async def carry_app(self) -> None:
        while True:
            active = self.state.get("active") or {}
            on_air_app = self.lease and active.get("source") == "app"
            self.mode = "app" if on_air_app else ("paltalk" if self.joined else "idle")
            key = f"{active.get('sessionId')}/{active.get('trackName')}" if on_air_app else None
            if key != self.pull_key or (self.pull_pc is not None and self.pull_pc.connectionState == "failed"):
                await self._drop_pull()
                if key:
                    try:
                        self.pull_pc, track = await pull(self.worker, active["sessionId"], active["trackName"])
                        targets = [self.app_audio] + ([self.programme.buffer] if self.programme else [])
                        self.pull_task = asyncio.ensure_future(drain(track, *targets))
                        self.pull_key = key
                        log("carrying the app broadcast")
                    except Exception as error:  # noqa: BLE001
                        log(f"could not pull the app broadcast: {error}")
            if not self.listen_only and self.joined:
                if on_air_app and not self.mic_held:
                    self.mic_held = await asyncio.to_thread(pt.RoomWriter().press_mic)
                    log("mic taken" if self.mic_held else "mic button not found")
                elif not on_air_app and self.mic_held:
                    await asyncio.to_thread(pt.RoomWriter().press_mic)
                    self.mic_held = False
                    log("mic released")
            await asyncio.sleep(1)

    async def _drop_pull(self) -> None:
        if self.pull_task:
            self.pull_task.cancel()
            self.pull_task = None
        if self.pull_pc is not None:
            await self.pull_pc.close()
            self.pull_pc = None
        self.pull_key = None
        self.app_audio.clear()

    async def post_cues(self) -> None:
        """App-origin cues into the room's chat (test room only)."""
        while True:
            stages = self.state.get("stages") or []
            if stages and self.posted_seq == 0:
                self.posted_seq = stages[-1]["seq"]  # do not replay history at start
            for event in stages:
                if event["seq"] <= self.posted_seq:
                    continue
                self.posted_seq = event["seq"]
                if self.listen_only or not self.joined or not self.lease or event["origin"] == "paltalk":
                    continue
                ok = await asyncio.to_thread(pt.RoomWriter().send_chat, event["stage"])
                log(f"posted cue {event['stage']!r}" if ok else f"cue {event['stage']!r} not confirmed in chat")
            await asyncio.sleep(1)

    async def mirror_platform_stage(self) -> None:
        """Cues called in the app (the platform's one cue list) into the
        room's chat, so Paltalk follows the app as the app follows Paltalk.
        A cue the relay itself just carried from the room is not echoed."""
        url = f"{self.cfg.get('PLATFORM_URL', 'https://darul-irfan-platform.wajidmahmoodali1984-e23.workers.dev').rstrip('/')}/v1/public/sheikh-stage"
        seen_at: str | None = None
        while True:
            await asyncio.sleep(5)
            if self.listen_only or not self.joined or not self.lease or self.halqah != "our-sheikh":
                continue
            try:
                data = await asyncio.to_thread(_get_json, url)
            except Exception:  # noqa: BLE001 - the network; next round
                continue
            stage = data.get("stage") or {}
            at, title = stage.get("at"), stage.get("title")
            if seen_at is None:
                seen_at = at or ""  # do not replay what was there before
                continue
            if not at or at <= seen_at or not title:
                continue
            seen_at = at
            if time.time() - self.last_cue_from_room < 20:
                continue  # our own cue, back from the platform
            ok = await asyncio.to_thread(pt.RoomWriter().send_chat, title)
            log(f"app cue {title!r} posted in the room" if ok else f"app cue {title!r} not confirmed in chat")

    # MARK: - Programme -> YouTube

    async def run_programme(self) -> None:
        """Keeps the YouTube/Facebook encoder up while the Halqah's Zikr is
        live on the platform (or the app is on air), with the stage picture
        re-captured whenever the stage changes."""
        if not self.programme:
            return
        url = f"{self.platform.rstrip('/')}/v1/public/live?ids={self.halqah}"
        platform_live = False
        while True:
            try:
                data = await asyncio.to_thread(_get_json, url)
                entry = next((h for h in data.get("halqahs", []) if h.get("id") == self.halqah), {})
                platform_live = bool(entry.get("live"))
            except Exception:  # noqa: BLE001 - a network blip keeps the stream as it is
                pass
            on_air_app = (self.state.get("active") or {}).get("source") == "app"
            live = self.lease and (platform_live or on_air_app)
            if live:
                picture = await asyncio.to_thread(self.picture.refresh)
                if picture:
                    self.programme.set_picture(picture)
                    if self.camera:
                        await asyncio.to_thread(self.camera.set_picture, picture)
                self.programme.start()
            else:
                self.programme.stop()
                if self.camera:  # between sessions: the Silsila's resting frame, never an old stage
                    await asyncio.to_thread(self.camera.set_picture, (HERE / "daily_zikr_frame.png").read_bytes())
            await asyncio.sleep(5)

    # MARK: - Start

    async def open_devices(self) -> None:
        """Opens the cables, retrying: at sign-in Windows' audio service can
        come up a few seconds after the relay."""
        warned = False
        while True:
            # A Remote Desktop connection hides the server's own devices
            # (only "Remote Audio" remains) and the open streams die; when
            # the session returns to the console the cable comes back under
            # new device numbers. Start PortAudio over and reopen.
            dead = [s for s in (self.capture, self.mic_out) if s is not None and not s.stream.active]
            if dead:
                import sounddevice as sd
                for device in (self.capture, self.mic_out):
                    if device is not None:
                        try:
                            device.close()
                        except Exception:  # noqa: BLE001
                            pass
                self.capture = self.mic_out = None
                sd._terminate()
                sd._initialize()
                warned = False
                log("audio devices changed; reopening the cables")
            if self.capture is None:
                try:
                    self.capture = DeviceInput(self.capture_name, self.room_audio, tap=self._tap)
                    log(f"capturing the room from {self.capture_name!r}")
                except Exception as error:  # noqa: BLE001
                    if not warned:
                        log(f"room capture unavailable (retrying): {error}")
                    self.problem = self.problem or "room audio cable not available"
            if not self.listen_only and self.mic_out is None:
                try:
                    self.mic_out = DeviceOutput(self.mic_name, self.app_audio)
                    log(f"app broadcast plays into {self.mic_name!r}")
                except Exception as error:  # noqa: BLE001
                    if not warned:
                        log(f"mic cable unavailable (retrying): {error}")
            warned = True
            await asyncio.sleep(10)

    # MARK: - Audio picker (the stage from the room's sound)

    def _feed_picker(self) -> None:
        """48 kHz stereo blocks from the room's cable -> 16 kHz mono."""
        while True:
            block = self.picker_audio.get()
            mono = block.astype(np.float32).mean(axis=1)
            mono = mono[: len(mono) // 3 * 3].reshape(-1, 3).mean(axis=1)
            try:
                self.picker.feed(mono.astype(np.int16))
            except Exception as error:  # noqa: BLE001 - the typed cues still carry the stage
                log(f"[picker] {error}")

    def _picked(self, stage: str | None, why: str) -> None:
        """From the picker's threads: a stage it heard, or why it gave none."""
        if stage is None:
            log(f"[picker] {why}")
            return
        if not (self.lease and self.joined and self.platform_is_live) or self.mode == "app":
            log(f"[picker] heard {stage} ({why}) but no Zikr is being relayed")
            return
        if self.dua_shown:
            log(f"[picker] heard {stage} ({why}) during the dua: ignored")
            return
        log(f"[picker] {stage}: {why}")
        self.platform_stage, self.stage_set_at = stage, time.time()
        self.heard_at[stage] = time.time()
        stage_id = self.cfg.get("SHAJRA_STAGE_ID", "shajra") if stage == "shajra" else stage
        if self.loop:
            self.loop.call_soon_threadsafe(lambda: asyncio.ensure_future(self._send_cue(stage_id, f"heard: {stage}")))

    async def follow_platform(self) -> None:
        """The platform's live state and current stage: where the picker
        steps from, and what makes a typed cue unnecessary."""
        url = f"{self.platform.rstrip('/')}/v1/public/live?ids={self.halqah}"
        while True:
            try:
                data = await asyncio.to_thread(_get_json, url)
                entry = next((h for h in data.get("halqahs", []) if h.get("id") == self.halqah), {})
                live = bool(entry.get("live"))
                if live != self.platform_is_live:
                    log(f"[platform] Zikr {'live' if live else 'not live'}")
                    self._new_session(live)  # a session began or ended
                self.platform_is_live = live
                # Our own stage, just set, is newer than a read that may
                # predate it.
                if time.time() - self.stage_set_at > 8:
                    self.platform_stage = (entry.get("stage") or {}).get("stageID") if live else None
            except Exception:  # noqa: BLE001 - the network; next round
                pass
            await asyncio.sleep(3)

    async def _typed_cue(self, stage: str, text: str) -> None:
        """A host's typed cue is the backup: the picker leads. It is dropped
        when the stage is already on, was heard lately, or lies behind the
        current one; otherwise it waits for the picker's reading first."""
        for wait in (0, 15):  # the picker reads a call within a few seconds; 15 s covers its last reading
            await asyncio.sleep(wait)
            if not self.picker:
                break
            if self.platform_stage == stage or time.time() - self.heard_at.get(stage, 0) < 300:
                log(f"typed cue {stage}: already heard")
                return
            if self.platform_stage and stage in ORDER and not ahead(stage, self.platform_stage):
                log(f"typed cue {stage}: behind the stage ({self.platform_stage})")
                return
        await self._send_cue(stage, text)
        self.platform_stage, self.stage_set_at = stage, time.time()

    async def run(self) -> None:
        log(f"relay {self.id} starting ({'listen-only' if self.listen_only else 'two-way'}; room {self.room!r})")
        self.loop = asyncio.get_running_loop()
        if self.camera:
            # Up for good: stopping it while Paltalk holds it hangs Paltalk.
            await asyncio.to_thread(self.camera.set_picture, (HERE / "daily_zikr_frame.png").read_bytes())
            await asyncio.to_thread(self.camera.start)
        await asyncio.gather(self.follow_platform(), self.open_devices(), self.keep_lease(), self.follow_state(), self.report(),
                             self.watch_room(), self.publish_room(), self.carry_app(),
                             self.post_cues(), self.mirror_platform_stage(), self.run_programme())

    def _tap(self, samples: np.ndarray) -> None:
        """While Paltalk is on air, the room is the programme's sound and
        what the audio picker listens to."""
        if self.picker and self.mode != "app":
            self.picker_audio.put(samples.copy())
        if self.programme and self.mode != "app":
            self.programme.buffer.write(samples)


def main() -> int:
    # Started windowless (pythonw) by the scheduled task, so nothing covers
    # Paltalk on the screen: write the log ourselves, in UTF-8 for Urdu cues.
    if sys.stdout is None or "--log" in sys.argv:
        log_file = open(HERE / "relay.log", "a", encoding="utf-8", buffering=1)  # noqa: SIM115 - lives as long as the process
        sys.stdout = sys.stderr = log_file
    cfg = settings()
    for name in ("WORKER_URL", "RELAY_KEY"):
        if not cfg.get(name):
            log(f"{name} is not set (relay.env)")
            return 2
    if len(sys.argv) > 1 and sys.argv[1] == "--dump-controls":
        pt.dump_controls(HERE / "paltalk_controls.txt")
        log("wrote paltalk_controls.txt")
        return 0
    asyncio.run(Relay(cfg).run())
    return 0


if __name__ == "__main__":
    sys.exit(main())
