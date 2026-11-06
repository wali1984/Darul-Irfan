"""Offline checks of the relay's room logic (no Paltalk, no network).

Replays what Paltalk showed on 6 November and the other ways a session ends,
against relay_agent.Relay.watch_room with a fake clock:

    python tests/test_room_logic.py

Each scenario prints PASS or FAIL; the exit code is the number of failures."""

from __future__ import annotations

import asyncio
import sys
import types
from pathlib import Path

RELAY = Path(__file__).resolve().parents[1] / "relay"
sys.path.insert(0, str(RELAY))

# The relay's audio and WebRTC modules are not needed here.
for name in ("aiortc", "aiortc.mediastreams", "av"):
    sys.modules.setdefault(name, types.ModuleType(name))
audio_io = types.ModuleType("audio_io")


class _Buffer:
    def __init__(self, *a, **k):
        self.last_sound = 0.0

    def take_peak(self):
        return 0

    def write(self, *_):
        pass


audio_io.PcmBuffer = _Buffer
audio_io.BufferTrack = audio_io.DeviceInput = audio_io.DeviceOutput = object
audio_io.drain = None
sys.modules["audio_io"] = audio_io
live_client = types.ModuleType("live_client")
live_client.ApiError = Exception
live_client.Worker = lambda *a, **k: types.SimpleNamespace(call=None)
live_client.publish = live_client.pull = None
sys.modules["live_client"] = live_client
programme = types.ModuleType("programme")
programme.Programme = object
sys.modules["programme"] = programme
stage_picture = types.ModuleType("stage_picture")
stage_picture.StagePicture = lambda *a, **k: None
sys.modules["stage_picture"] = stage_picture
audio_picker = types.ModuleType("audio_picker")
audio_picker.ORDER = ["tasbih", "latifa-1", "latifa-2", "latifa-3", "latifa-4", "latifa-5", "latifa-6", "latifa-7",
                      "raabta", "ahadiyat", "maiyyat", "aqrabiyyat", "sair-kaaba", "rauza-athar", "masjid-nabawi", "shajra"]
audio_picker.ahead = lambda a, b: b is None or audio_picker.ORDER.index(a) > audio_picker.ORDER.index(b)
sys.modules["audio_picker"] = audio_picker

import relay_agent as ra  # noqa: E402

pt = ra.pt


class Clock:
    def __init__(self):
        self.now = 1_000_000.0


class Stop(Exception):
    pass


def build(statuses, speaker=None, chat=None, platform_live=False, stage=None, rounds=None):
    """A Relay whose Paltalk shows `statuses` (one per round)."""
    clock = Clock()
    calls = {"join": 0, "press": 0, "dua": 0, "start": 0, "cues": []}
    script = list(statuses)
    speaker_script = list(speaker or [])
    chat_script = list(chat or [])
    rounds = rounds or len(script)

    ra.time.time = lambda: clock.now

    async def fake_sleep(seconds):
        clock.now += max(seconds, 0)

    ra.asyncio.sleep = fake_sleep
    ra.DUA_FILE = Path(__file__).with_name("_dua_test.txt")
    ra.DUA_FILE.unlink(missing_ok=True)
    ra.PENDING_FILE = Path(__file__).with_name("_pending_test.json")
    ra.PENDING_FILE.unlink(missing_ok=True)

    async def to_thread(fn, *args, **kwargs):
        return fn(*args, **kwargs)

    ra.asyncio.to_thread = to_thread
    pt.ensure_running = lambda: None
    view = types.SimpleNamespace(ok=True, seconds=0.5, first=lambda **k: None)
    pt.look = lambda: view

    def status(_view, _markers, _room=""):
        if not script:
            raise Stop
        return script.pop(0)

    pt.room_status = status
    pt.close_popups_in = lambda v: False
    pt.signed_in_view = lambda v: True
    pt.dismiss_prompt = lambda: False
    pt.login_form = lambda: False
    pt.remote_desktop_connected = lambda: False

    def try_join(*a):
        calls["join"] += 1
        return True

    pt.try_join = try_join
    def read_icon(*_):
        return speaker_script.pop(0) if speaker_script else (speaker_script_default[0])

    speaker_script_default = [speaker_script[-1] if speaker_script else True]
    pt.speaker_on = read_icon
    pt.icon_on = read_icon
    pt.speaker_icon = lambda v: object()

    def leave(_view, _room):
        calls["leave"] = calls.get("leave", 0) + 1
        return True

    pt.leave_room = leave

    def press(v):
        calls["press"] += 1
        return True

    pt.press_speaker = press

    class Follower:
        def new(self, v):
            return chat_script.pop(0) if chat_script else []

    pt.MessageFollower = Follower
    cfg = {"WORKER_URL": "http://x", "RELAY_KEY": "k", "PLATFORM_CUE_TOKEN": "t", "AUDIO_PICKER": "0",
           "CUE_HOSTS": "ameer_imam,ghazi_faiz", "PALTALK_ROOM": "Our Sheikh", "PALTALK_USER": "Our Shiekh TEST"}
    relay = ra.Relay(cfg)
    relay.lease = True
    relay.lease_deadline = float("inf")  # the lease holds for the whole scenario (the monotonic clock is real here)
    relay.platform_is_live = platform_live
    relay.platform_stage = stage

    def start(title):
        calls["start"] += 1
        return 201, "{}"

    def dua():
        calls["dua"] += 1
        return 200, "{}"

    def post(stage_id, cue_id=None):
        calls["cues"].append(stage_id)
        return 201, "{}"

    relay.platform_cues.start, relay.platform_cues.dua, relay.platform_cues.post = start, dua, post

    async def worker_call(*a, **k):
        return {}

    relay.worker.call = worker_call
    return relay, calls, clock


def run(relay):
    async def go():
        try:
            await relay.watch_room()
        except Stop:
            pass
        await asyncio.sleep(0)
        # let scheduled typed cues finish
        for task in [t for t in asyncio.all_tasks() if t is not asyncio.current_task()]:
            try:
                await task
            except Exception:  # noqa: BLE001
                pass
    asyncio.run(go())


failures = 0


def check(name, ok, detail=""):
    global failures
    print(f"{'PASS' if ok else 'FAIL'}  {name}{'' if ok else '  ' + detail}")
    failures += 0 if ok else 1


IN = ("in", "room open")
UNKNOWN = ("unknown", "walk: COMError")
OUT = ("out", "no room open in Paltalk")
CLOSED = ("closed", "Paltalk says the room is not open")

# 1. 6 November: a minute of failed reads in the middle of the Zikr.
relay, calls, _ = build([IN] * 3 + [UNKNOWN] * 30 + [IN] * 3, platform_live=True)
run(relay)
check("failed reads never leave the room", relay.joined == "room open" and calls["join"] == 0 and calls["dua"] == 0,
      f"joined={relay.joined} joins={calls['join']} dua={calls['dua']}")

# 2. A blip of "no room" shorter than LEAVE_AFTER is not leaving.
relay, calls, _ = build([IN] * 3 + [OUT] * 5 + [IN] * 3, platform_live=True)
run(relay)
check("a short 'no room' blip is not leaving", relay.joined == "room open" and calls["join"] == 0)

# 3. Really out of the room: left after LEAVE_AFTER, then rejoins, never a dua.
relay, calls, _ = build([IN] * 3 + [OUT] * 40, platform_live=True)
run(relay)
check("out for real: leaves, tries to rejoin, no dua", relay.joined is None and calls["join"] >= 1 and calls["dua"] == 0,
      f"joined={relay.joined} joins={calls['join']} dua={calls['dua']}")

# 4. The room closes after the Zikr: Paltalk's notice twice, a join apart -> one dua.
relay, calls, _ = build([IN] * 3 + [CLOSED] + [OUT] * 32 + [CLOSED] + [OUT] * 5 + [CLOSED], platform_live=True)
run(relay)
check("room closed (seen twice): one dua", calls["dua"] == 1, f"dua={calls['dua']}")

# 5. A single "closed" notice (a failed join of an open room) is not the end.
relay, calls, _ = build([IN] * 3 + [CLOSED] + [IN] * 10, platform_live=True)
run(relay)
check("one 'closed' notice alone sends no dua", calls["dua"] == 0, f"dua={calls['dua']}")

# 5b. Joining a closed room flashes the room once before "not open": not a join, no start.
relay, calls, _ = build([OUT] * 3 + [IN] + [CLOSED] + [OUT] * 5)
run(relay)
check("a closed room's flash is not a join", relay.joined is None and calls["start"] == 0 and relay.joined_at == 0.0,
      f"joined={relay.joined} starts={calls['start']}")

# 6. Speaker muted at join: one press, kept when the icon turns green.
relay, calls, _ = build([IN] * 10, speaker=[False, True, True, True])
run(relay)
check("muted at join: switched on with one press", calls["press"] == 1 and relay.speaker_state is True,
      f"presses={calls['press']} state={relay.speaker_state}")

# 7. Speaker cannot be confirmed: the press is undone (never left guessing).
relay, calls, _ = build([IN] * 10, speaker=[False, False] + [False] * 20)
run(relay)
check("unconfirmed press is undone", calls["press"] % 2 == 0 and calls["press"] >= 2, f"presses={calls['press']}")

# 7b. Two unconfirmed presses, then no more (6 November: twice a minute for an hour).
relay, calls, clock = build([IN] * 60, speaker=[False] * 2000)
run(relay)
check("unconfirmed presses stop after two tries", calls["press"] == 4 and relay.speaker_tries == 2 and "speaker" in (relay.problem or ""),
      f"presses={calls['press']} tries={relay.speaker_tries} problem={relay.problem}")

# 7c. ...and after 10 minutes in that room the relay leaves it once to join again.
relay, calls, clock = build([IN] * 400, speaker=[False] * 4000)
run(relay)
check("a room whose speaker cannot be switched on is rejoined once (then two fresh tries)",
      calls.get("leave", 0) == 1 and calls["press"] == 8 and relay.joined == "room open",
      f"leaves={calls.get('leave', 0)} presses={calls['press']} joined={relay.joined}")

# 7d. Paltalk's own "Reconnecting" dialog: not the room, not leaving it; after 4 minutes Paltalk is started over, once.
RECONNECTING = ("unknown", "Paltalk is reconnecting to its servers")
relay, calls, clock = build([IN] * 3 + [RECONNECTING] * 200)

def restart():
    calls["restart"] = calls.get("restart", 0) + 1

pt.restart = restart
run(relay)
check("Paltalk stuck reconnecting is started over once", calls.get("restart", 0) == 1 and calls["dua"] == 0 and relay.joined is None,
      f"restarts={calls.get('restart', 0)} dua={calls['dua']} joined={relay.joined}")

# 8. Speaker unreadable (screen not drawn): never pressed.
relay, calls, _ = build([IN] * 10, speaker=[None] * 20)
run(relay)
check("unreadable speaker is never pressed", calls["press"] == 0, f"presses={calls['press']}")

# 9. Chat: "Astaghfirullah" from a host is not a cue; "2nd" is; the same cue twice counts once.
relay, calls, _ = build([IN] * 12, platform_live=True, stage="latifa-1",
                        chat=[[], [("ghazi_faiz", "Astaghfirullah")], [("ameer_imam", "2nd")], [("ameer_imam", "2nd")]])
run(relay)
check("host 'Astaghfirullah' is not a cue", "istighfar" not in calls["cues"], f"cues={calls['cues']}")
check("host '2nd' is one cue", calls["cues"].count("latifa-2") == 1, f"cues={calls['cues']}")

# 10. Members' aameen after the last Muraqaba shows the dua (a cue), without ending the session.
relay, calls, _ = build([IN] * 8, platform_live=True, stage="masjid-nabawi",
                        chat=[[], [("a", "aameen"), ("b", "Ameen")], [("c", "آمین")]])
run(relay)
check("aameen after the last Muraqaba shows the dua", "dua" in calls["cues"] and calls["dua"] == 0,
      f"cues={calls['cues']} dua={calls['dua']}")

# 11. Aameen in the middle of the Latifas is not the dua.
relay, calls, _ = build([IN] * 8, platform_live=True, stage="latifa-3",
                        chat=[[], [("a", "aameen"), ("b", "Ameen")], [("c", "آمین")]])
run(relay)
check("aameen mid-Zikr is not the dua", "dua" not in calls["cues"], f"cues={calls['cues']}")

# 12. Start: an open, silent room does not start the Zikr; sound for START_VOICE does.
relay, calls, clock = build([IN] * 6)
run(relay)
check("an open room starts the Zikr at once, once", calls["start"] == 1, f"starts={calls['start']}")
relay, calls, clock = build([IN] * 8)


class Loud(_Buffer):
    @property
    def last_sound(self):
        return clock.now

    @last_sound.setter
    def last_sound(self, value):
        pass


relay.room_audio = Loud()
run(relay)
check("sound in the room changes nothing: still one start", calls["start"] == 1, f"starts={calls['start']}")

ra.DUA_FILE.unlink(missing_ok=True)
ra.PENDING_FILE.unlink(missing_ok=True)
print(f"{failures} failure(s)")
sys.exit(failures)
