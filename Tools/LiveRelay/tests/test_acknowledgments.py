"""Offline checks that the relay moves its own state only on the platform's
acknowledgment, tries again what the network or the platform failed, and
lets no stale work (an old generation, a lost lease, a left room) reach the
platform. The 6 November audit reproduced four defects against the room
harness; here they are the other way round, as what must hold now.

    python tests/test_acknowledgments.py

Reuses tests/test_room_logic.py's harness (no Paltalk, no network, a fake
clock); that file runs its own 17 checks as it loads, and they must pass
too. Each case prints PASS or FAIL; the exit code is the number of failures."""

from __future__ import annotations

import asyncio
import contextlib
import importlib.util
import io
import json
import sys
import threading
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent

spec = importlib.util.spec_from_file_location("room_logic", HERE / "test_room_logic.py")
m = importlib.util.module_from_spec(spec)
room_output = io.StringIO()
with contextlib.redirect_stdout(room_output):
    try:
        spec.loader.exec_module(m)
    except SystemExit as exit_:
        if exit_.code:
            print(room_output.getvalue())
            sys.exit(exit_.code)
room_checks = sum(1 for line in room_output.getvalue().splitlines() if line.startswith("PASS"))
print(f"test_room_logic.py: {room_checks} checks passed")

ra = m.ra
IN, OUT, CLOSED = m.IN, m.OUT, m.CLOSED

logs: list[str] = []
sleeps: list[float] = []
real_log = ra.log


def log(message: str) -> None:
    logs.append(message)
    real_log(message)


ra.log = log


def build(*args, **kwargs):
    """The harness's relay, with its log lines and sleeps on record."""
    relay, calls, clock = m.build(*args, **kwargs)
    logs.clear()
    sleeps.clear()
    fake_sleep = ra.asyncio.sleep

    async def sleep(seconds):
        sleeps.append(seconds)
        await fake_sleep(seconds)

    ra.asyncio.sleep = sleep
    return relay, calls, clock


failures = 0


def check(name, ok, detail=""):
    global failures
    print(f"{'PASS' if ok else 'FAIL'}  {name}{'' if ok else '  ' + detail}")
    failures += 0 if ok else 1


def said(fragment: str) -> int:
    return sum(1 for line in logs if fragment in line)


def answers(*statuses):
    """A platform that answers these in turn (the last one for good) and
    keeps every call: (stage, cue id) for a cue, () for the dua."""
    attempts: list[tuple] = []
    script = list(statuses)
    words = {503: "unavailable", 401: "bad token", 403: "refused", 404: "refused", 429: "slow down",
             409: "no live Zikr on the platform", 0: "URLError"}

    def answer(*args):
        attempts.append(args)
        status = script.pop(0) if len(script) > 1 else script[0]
        return status, words.get(status, "{}")

    return answer, attempts


async def settle():
    """Lets what was scheduled on the loop run to its end (the harness's
    fake sleep never yields, so a task starts only when something does)."""
    loop = asyncio.get_running_loop()
    for _ in range(3):
        turn = loop.create_future()
        loop.call_soon(turn.set_result, None)
        await turn
    for task in [t for t in asyncio.all_tasks() if t is not asyncio.current_task()]:
        with contextlib.suppress(Exception):
            await task


# 1. Audit: "close command 503 is never retried". The dua for a closed room is
#    tried again every 10 s until the platform takes it (contract test 4).
async def close_dua():
    r, c, clock = build([], platform_live=True)
    dua, attempts = answers(503, 503, 200)
    r.platform_cues.dua = dua
    r.was_in_session = True
    await r._room_closed(clock.now)  # the first "not open"
    clock.now += 46
    await r._room_closed(clock.now)  # seen again: the first try, which fails
    sent_after_failure = r.close_dua_sent
    clock.now += 5
    await r._room_closed(clock.now)  # too soon for another try
    tries_after_5s = len(attempts)
    clock.now += 5
    await r._room_closed(clock.now)  # the second try fails too
    clock.now += 10
    await r._room_closed(clock.now)  # the third is taken
    check("close dua 503, 503, 200: tried again every 10 s, close_dua_sent only after the 200",
          len(attempts) == 3 and tries_after_5s == 1 and not sent_after_failure and r.close_dua_sent and r.dua_given,
          f"attempts={len(attempts)} after5s={tries_after_5s} sent_after_failure={sent_after_failure} sent={r.close_dua_sent}")
    clock.now += 10
    await r._room_closed(clock.now)
    check("close dua: once taken, no more tries", len(attempts) == 3, f"attempts={len(attempts)}")

    r, c, clock = build([], platform_live=True)
    dua, attempts = answers(409)
    r.platform_cues.dua = dua
    r.was_in_session = True
    await r._room_closed(clock.now)
    clock.now += 46
    await r._room_closed(clock.now)
    check("close dua 409 (nothing live to end) counts as done", r.close_dua_sent and len(attempts) == 1,
          f"sent={r.close_dua_sent} attempts={len(attempts)}")

    r, c, clock = build([], platform_live=True)
    dua, attempts = answers(503)
    r.platform_cues.dua = dua
    r.was_in_session = True
    await r._room_closed(clock.now)
    clock.now += 46
    for _ in range(80):
        await r._room_closed(clock.now)
        clock.now += 10
    check("close dua failing for 10 minutes: 61 tries, then given up with a problem",
          r.close_dua_given_up and not r.close_dua_sent and len(attempts) == 61
          and "did not take the dua" in (r.platform_problem or ""),
          f"given_up={r.close_dua_given_up} attempts={len(attempts)} problem={r.platform_problem}")

    r, c, clock = build([], platform_live=True)
    dua, attempts = answers(401)
    r.platform_cues.dua = dua
    r.was_in_session = True
    await r._room_closed(clock.now)
    clock.now += 46
    for _ in range(5):
        await r._room_closed(clock.now)
        clock.now += 10
    check("close dua 401: one try, the token problem, no more tries",
          len(attempts) == 1 and r.close_dua_given_up and r.platform_problem == ra.TOKEN_REFUSED,
          f"attempts={len(attempts)} problem={r.platform_problem}")

    r, c, clock = build([], platform_live=True)
    dua, attempts = answers(200)
    r.platform_cues.dua = dua
    r.was_in_session = True
    await r._room_closed(clock.now)
    r._lease_lost("test")
    clock.now += 46
    await r._room_closed(clock.now)  # no lease: nothing
    r.lease = True
    await r._room_closed(clock.now)  # the lease is back, but the closing was seen a generation ago
    check("close dua after the lease was lost meanwhile: dropped as stale, never sent",
          len(attempts) == 0 and said("close dua dropped (stale") == 1 and r.first_closed_at is None,
          f"attempts={len(attempts)} logs={[l for l in logs if 'stale' in l]}")


# 2. Audit: "dua shown flag stays set despite six rejected writes". dua_shown
#    follows the platform's acknowledgment of the "dua" cue (contract test 4).
async def dua_cue():
    r, c, clock = build([], platform_live=True, stage="masjid-nabawi")
    r.joined = "room open"
    post, attempts = answers(503)
    r.platform_cues.post = post
    await r._show_dua("test")
    await r._show_dua("test again")  # while the first is on its way
    await r.dua_task
    check("dua cue refused six times: dua_shown stays False, one cue id, backoff 2/4/8/16/30 s",
          not r.dua_shown and len(attempts) == 6 and len({a[1] for a in attempts}) == 1
          and [s for s in sleeps if s >= 2] == [2, 4, 8, 16, 30],
          f"shown={r.dua_shown} attempts={len(attempts)} ids={len({a[1] for a in attempts})} sleeps={sleeps}")
    check("...and the cue is kept on disk for a restart", ra.PENDING_FILE.exists() and len(r.pending) == 1,
          f"file={ra.PENDING_FILE.exists()} pending={r.pending}")
    post, attempts = answers(201)
    r.platform_cues.post = post
    await r._show_dua("later")
    await r.dua_task
    check("a later success shows the dua", r.dua_shown and len(attempts) == 1 and not ra.PENDING_FILE.exists(),
          f"shown={r.dua_shown} attempts={len(attempts)}")


# 3. Audit: "queued typed cue can post after loss of lease and room". Work of
#    an older generation, or without the lease or the room, never posts
#    (contract test 6).
async def stale_work():
    r, c, clock = build([], platform_live=True, stage="latifa-1")
    r.lease = False
    r.joined = None
    await r._typed_cue("latifa-2", "2nd")
    check("typed cue after the lease and the room are lost: nothing posted",
          c["cues"] == [] and said("dropped (stale: no lease") == 1 and r.platform_stage == "latifa-1",
          f"cues={c['cues']} stage={r.platform_stage}")

    r, c, clock = build([], platform_live=True, stage="latifa-1")
    r.joined = "room open"
    task = asyncio.ensure_future(r._typed_cue("latifa-2", "2nd", r.generation))
    r._left("test")
    r.joined = "room open"  # back in the room, but the cue is of the generation before
    await task
    check("typed cue queued before the room was left: dropped as stale",
          c["cues"] == [] and said("dropped (stale: generation") == 1, f"cues={c['cues']}")

    r, c, clock = build([], platform_live=True, stage="latifa-1")
    r.joined = "room open"
    post, attempts = answers(503, 201)
    r.platform_cues.post = post
    fake = ra.asyncio.sleep

    async def sleep_into_a_new_session(seconds):
        if seconds >= 2:
            r._new_session(True)
        await fake(seconds)

    ra.asyncio.sleep = sleep_into_a_new_session
    await r._typed_cue("latifa-2", "2nd")
    ra.asyncio.sleep = fake
    check("a retry asleep when the platform's session changes: not posted again",
          len(attempts) == 1 and said("dropped (stale: generation") == 1 and r.platform_stage == "latifa-1",
          f"attempts={len(attempts)} stage={r.platform_stage}")

    r, c, clock = build([], platform_live=True, stage="latifa-1")
    r.joined = "room open"
    r.loop = asyncio.get_running_loop()
    r._picked("latifa-2", "a call")
    r._new_session(True)  # the platform's session changed before the loop sent it
    await settle()
    check("picker result queued before the session changed: not posted",
          c["cues"] == [] and r.platform_stage == "latifa-1" and "latifa-2" not in r.heard_at,
          f"cues={c['cues']} stage={r.platform_stage}")
    r._picked("latifa-3", "a call")
    await settle()
    check("picker result of this generation: posted, then the stage is this relay's own",
          c["cues"] == ["latifa-3"] and r.platform_stage == "latifa-3" and "latifa-3" in r.heard_at,
          f"cues={c['cues']} stage={r.platform_stage}")


# 4. Audit: "local stage advances after all remote cue writes fail". The stage
#    stays at the platform's until the platform takes the cue (contract test 5).
async def stage_on_acknowledgment():
    r, c, clock = build([], platform_live=True, stage="latifa-1")
    r.joined = "room open"
    post, attempts = answers(503)
    r.platform_cues.post = post
    await r._typed_cue("latifa-2", "2nd")
    check("every cue POST fails: stage unchanged, six tries with one id, each retry said",
          r.platform_stage == "latifa-1" and len(attempts) == 6 and len({a[1] for a in attempts}) == 1
          and said("again in") == 5 and said("not delivered") == 1,
          f"stage={r.platform_stage} attempts={len(attempts)} retries_said={said('again in')}")
    post, attempts = answers(0, 429, 201)
    r.platform_cues.post = post
    await r._typed_cue("latifa-2", "2nd")
    check("a network error and a 429 are retried; the stage is ours on the 201",
          r.platform_stage == "latifa-2" and len(attempts) == 3 and r.stage_set_at == clock.now,
          f"stage={r.platform_stage} attempts={len(attempts)}")

    r, c, clock = build([], platform_live=True, stage="latifa-1")
    r.joined = "room open"
    post, attempts = answers(503)
    r.platform_cues.post = post
    await r._heard("latifa-2", "latifa-2", r.generation)
    check("the picker's cue not taken: stage and heard_at unchanged",
          r.platform_stage == "latifa-1" and not r.heard_at, f"stage={r.platform_stage} heard={r.heard_at}")
    post, attempts = answers(201)
    r.platform_cues.post = post
    await r._heard("latifa-2", "latifa-2", r.generation)
    check("the picker's cue taken: stage and heard_at set",
          r.platform_stage == "latifa-2" and r.heard_at.get("latifa-2") == clock.now,
          f"stage={r.platform_stage} heard={r.heard_at}")


# 5. A refused token stops after one try, with a problem; 404 stops too.
async def refused():
    r, c, clock = build([], platform_live=True, stage="latifa-1")
    r.joined = "room open"
    post, attempts = answers(401)
    r.platform_cues.post = post
    await r._typed_cue("latifa-2", "2nd")
    check("401: one try, then the problem says the token was refused",
          len(attempts) == 1 and r.problem == ra.TOKEN_REFUSED and r.platform_problem == ra.TOKEN_REFUSED
          and said(ra.TOKEN_REFUSED) == 1 and r.platform_stage == "latifa-1" and not ra.PENDING_FILE.exists(),
          f"attempts={len(attempts)} problem={r.problem} said={said(ra.TOKEN_REFUSED)}")
    await r._typed_cue("latifa-3", "3rd")
    check("...said once", len(attempts) == 2 and said(ra.TOKEN_REFUSED) == 1,
          f"attempts={len(attempts)} said={said(ra.TOKEN_REFUSED)}")
    post, attempts = answers(403)
    r.platform_cues.post = post
    await r._typed_cue("latifa-4", "4th")
    check("403 the same", len(attempts) == 1 and r.platform_problem == ra.TOKEN_REFUSED, f"attempts={len(attempts)}")
    post, attempts = answers(201)
    r.platform_cues.post = post
    await r._typed_cue("latifa-5", "5th")
    check("a success clears the problem", r.platform_problem is None and said("takes the relay's writes again") == 1,
          f"problem={r.platform_problem}")

    r, c, clock = build([], platform_live=True, stage="latifa-1")
    r.joined = "room open"
    post, attempts = answers(404)
    r.platform_cues.post = post
    await r._typed_cue("latifa-2", "2nd")
    check("404: one try, logged, no token problem",
          len(attempts) == 1 and r.platform_problem is None and said("refused by the platform (404)") == 1
          and not ra.PENDING_FILE.exists(), f"attempts={len(attempts)} problem={r.platform_problem}")


# 6. The lease by the Worker's clock: a failed call extends nothing; past the
#    deadline has_lease is False, "lease expired" is said and the generation
#    steps once.
async def lease():
    r, c, clock = build([])
    r.lease, r.lease_deadline = False, 0.0

    async def grant(method, path, body=None):
        return {"granted": True, "until": 25_000.0, "state": {"now": 5_000.0}}  # 20 s left, by the Worker's clock

    r.worker.call = grant
    await r._lease_round()
    left = r.lease_deadline - time.monotonic()
    check("a grant: has_lease, 20 s less the 3 s margin on the monotonic clock",
          r.has_lease and r.lease and 16.5 < left <= 17.0 and r.generation == 0 and r.lease_until == 25_000.0
          and said("holding the lease") == 1, f"has={r.has_lease} left={left:.2f} generation={r.generation}")

    async def fail(*a, **k):
        raise OSError("network")

    r.worker.call = fail
    deadline = r.lease_deadline
    await r._lease_round()
    check("a failed lease call extends nothing and loses nothing yet",
          r.lease_deadline == deadline and r.has_lease and said("lease call failed") == 1,
          f"deadline_moved={r.lease_deadline != deadline} has={r.has_lease}")
    r.lease_deadline = time.monotonic() - 0.01
    gone_at_once = not r.has_lease
    await r._lease_round()
    check("the deadline passes: has_lease False at once, 'lease expired' said, one new generation",
          gone_at_once and not r.lease and r.generation == 1 and said("lease expired") == 1,
          f"gone_at_once={gone_at_once} lease={r.lease} generation={r.generation}")
    await r._lease_round()
    check("...and only once", r.generation == 1 and said("lease expired") == 1, f"generation={r.generation}")
    r.worker.call = grant
    await r._lease_round()
    check("granted again: holding it, the generation as it was", r.has_lease and r.generation == 1,
          f"has={r.has_lease} generation={r.generation}")

    async def other(*a, **k):
        return {"granted": False, "holder": "relay-b"}

    r.worker.call = other
    await r._lease_round()
    check("lost to another relay: standby, a new generation",
          not r.has_lease and r.generation == 2 and said("lease held by relay-b") == 1,
          f"has={r.has_lease} generation={r.generation}")

    async def bare(*a, **k):
        return {"granted": True}

    r.worker.call = bare
    await r._lease_round()
    left = r.lease_deadline - time.monotonic()
    check("a grant that does not say when it ends: the Worker's 20 s less the margin", 16.5 < left <= 17.0,
          f"left={left:.2f}")


# 7. Cues the platform never took are kept for a restart, and sent again with
#    their ids only once the platform is live and the relay holds the lease
#    and is in the room.
async def pending_across_restart():
    r, c, clock = build([], platform_live=True, stage="latifa-1")
    r.joined = "room open"
    post, attempts = answers(503)
    r.platform_cues.post = post
    await r._typed_cue("latifa-2", "2nd")
    saved = json.loads(ra.PENDING_FILE.read_text(encoding="utf-8"))
    cue = next(iter(saved.values()), {})
    check("a cue the platform never took is on disk with its id",
          len(saved) == 1 and cue.get("stage") == "latifa-2" and cue.get("cue_id") == attempts[0][1], f"saved={saved}")

    r2, c2, clock2 = build([], platform_live=False)
    old = dict(cue, cue_id="old", created_at=clock2.now - 601)
    ra.PENDING_FILE.write_text(json.dumps({cue["cue_id"]: cue, "old": old}), encoding="utf-8")
    r2.pending = r2._load_pending()
    check("on start, cues older than 10 minutes are left out", list(r2.pending) == [cue["cue_id"]], f"pending={r2.pending}")
    post2, attempts2 = answers(201)
    r2.platform_cues.post = post2
    live = {"live": False}
    real_get_json = ra._get_json
    ra._get_json = lambda url: {"halqahs": [{"id": "our-sheikh", "live": live["live"], "stage": {"stageID": "latifa-1"}}]}
    fake = ra.asyncio.sleep

    async def one_round(seconds):
        raise m.Stop

    ra.asyncio.sleep = one_round
    r2.joined = "room open"
    with contextlib.suppress(m.Stop):
        await r2.follow_platform()
    ra.asyncio.sleep = fake
    await settle()
    check("the platform not live: not sent again", attempts2 == [] and r2.pending, f"attempts={attempts2}")
    live["live"] = True
    ra.asyncio.sleep = one_round
    with contextlib.suppress(m.Stop):
        await r2.follow_platform()
    ra.asyncio.sleep = fake
    ra._get_json = real_get_json
    await settle()
    check("the platform live, the lease held, in the room: sent again with its id, then forgotten",
          [a[1] for a in attempts2] == [cue["cue_id"]] and not r2.pending and not ra.PENDING_FILE.exists(),
          f"attempts={attempts2} pending={r2.pending}")


# 8. _dua says whether the platform has it.
async def dua_result():
    r, c, clock = build([], platform_live=True)
    results = []
    for status, expected in ((200, True), (201, True), (409, True), (503, False), (0, False)):
        r.platform_cues.dua = lambda s=status: (s, "x")
        results.append(await r._dua("test") is expected)
    check("_dua: 200/201/409 are done, the network and a 5xx are not", all(results), f"results={results}")


# 9. The audio picker: one worker thread, a short queue, stale readings skipped.
def picker_jobs():
    picker_spec = importlib.util.spec_from_file_location("audio_picker_real", HERE.parent / "relay" / "audio_picker.py")
    ap = importlib.util.module_from_spec(picker_spec)
    picker_spec.loader.exec_module(ap)
    heard = []
    picker = ap.Picker(lambda stage, why: heard.append(stage), lambda: "latifa-1")
    gate = threading.Event()

    def transcribe(clip, padded=False, language="ur"):
        gate.wait(5)
        return "دوسرا لطیفہ"

    picker.transcribe = transcribe
    clip = np.zeros(ap.RATE * 2, dtype=np.int16)
    picker.clock = 100.0
    picker._queue(picker._read, clip, "latifa-2", 1.0, 100.0, "quick")
    for _ in range(300):  # the worker takes the first reading and waits in transcribe
        if not picker.jobs:
            break
        time.sleep(0.01)
    for _ in range(6):
        picker._queue(picker._read, clip, "latifa-2", 1.0, 100.0, "quick")
    check("one worker thread; four readings wait at most, the oldest two dropped",
          picker.worker is not None and picker.worker.is_alive() and len(picker.jobs) == 4 and picker.dropped == 2,
          f"waiting={len(picker.jobs)} dropped={picker.dropped}")
    picker.reset()  # a new session while the first reading is in progress
    gate.set()
    time.sleep(0.5)
    check("a reading in progress at reset() gives no stage; the queued ones are gone", heard == [] and not picker.jobs,
          f"heard={heard} waiting={len(picker.jobs)}")
    stale = (picker.generation - 1, picker.clock, picker._read, (clip, "latifa-2", 1.0, picker.clock, "quick"))
    picker._run(stale)
    old = (picker.generation, picker.clock - 31, picker._read, (clip, "latifa-2", 1.0, picker.clock - 31, "quick"))
    picker._run(old)
    check("an old generation's reading and a clip over 30 s old are skipped", heard == [] and picker.skipped == 2,
          f"heard={heard} skipped={picker.skipped}")
    fresh = (picker.generation, picker.clock, picker._read, (clip, "latifa-2", 1.0, picker.clock, "quick"))
    picker._run(fresh)
    check("a reading of this generation gives its stage", heard == ["latifa-2"], f"heard={heard}")

    inline = ap.Picker(lambda stage, why: None, lambda: None, inline=True)
    inline.transcribe = lambda clip, padded=False, language="ur": ""
    inline._queue(inline._read, clip, "latifa-2", 1.0, 0.0, "quick")
    check("inline readings run on the feeding thread, no worker", inline.worker is None, f"worker={inline.worker}")


for case in (close_dua, dua_cue, stale_work, stage_on_acknowledgment, refused, lease, pending_across_restart, dua_result):
    asyncio.run(case())

# Through watch_room: a closed room's dua the platform failed twice goes on the
# third try, ten seconds apart, whatever Paltalk shows meanwhile.
relay, calls, clock = build([IN] * 3 + [CLOSED] + [OUT] * 32 + [CLOSED] + [OUT] * 12, platform_live=True)
dua, attempts = answers(503, 503, 200)
relay.platform_cues.dua = dua
m.run(relay)
check("watch_room: the closed room's dua is tried until taken", len(attempts) == 3 and relay.close_dua_sent,
      f"attempts={len(attempts)} sent={relay.close_dua_sent}")

# watch_room keeps a platform problem on show, round after round.
relay, calls, clock = build([IN] * 3, platform_live=True)
relay.platform_problem = ra.TOKEN_REFUSED
m.run(relay)
check("watch_room keeps the platform's problem on show", relay.problem == ra.TOKEN_REFUSED, f"problem={relay.problem}")

picker_jobs()

ra.DUA_FILE.unlink(missing_ok=True)
ra.PENDING_FILE.unlink(missing_ok=True)
print(f"{failures} failure(s)")
sys.exit(failures)
