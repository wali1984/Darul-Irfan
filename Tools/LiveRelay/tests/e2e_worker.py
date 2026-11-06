"""End-to-end check of the staging Worker with real WebRTC audio, no Windows
relay needed: a fake host (440 Hz) and a fake relay (660 Hz) publish, a
listener follows whatever is on air and the dominant pitch proves which.

    python tests/e2e_worker.py            (keys from ../../live-relay-staging.md)
"""

from __future__ import annotations

import asyncio
import sys
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "relay"))

from audio_io import PcmBuffer, ToneTrack, drain  # noqa: E402
from live_client import ApiError, Worker, publish, pull  # noqa: E402

BASE = "https://darul-irfan-live-staging.wajidmahmoodali1984-e23.workers.dev"
KEYS = {}
for line in (HERE.parents[3] / "live-relay-staging.md").read_text(encoding="utf-8").splitlines():
    name, sep, value = line.partition("=")
    if sep:
        KEYS[name.strip()] = value.strip()

host, relay, listen = Worker(BASE, KEYS["HOST_KEY"]), Worker(BASE, KEYS["RELAY_KEY"]), Worker(BASE, KEYS["LISTEN_KEY"])
failures = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"{'PASS' if ok else 'FAIL'}  {name}{('  ' + detail) if detail else ''}", flush=True)
    if not ok:
        failures.append(name)


async def hear(seconds: float = 4.0) -> tuple[float, float]:
    """Pulls what is on air and returns (dominant Hz, rms)."""
    state = await listen.call("GET", "/api/state")
    active = state["active"]
    if not active["source"]:
        return 0.0, 0.0
    pc, track = await pull(listen, active["sessionId"], active["trackName"])
    buffer = PcmBuffer(max_seconds=10)
    task = asyncio.ensure_future(drain(track, buffer))
    await asyncio.sleep(seconds)
    task.cancel()
    await pc.close()
    samples = buffer.read(buffer.frames)[:, 0].astype(np.float32)
    samples = samples[len(samples) // 3:]
    if len(samples) < 4800:
        return 0.0, 0.0
    spectrum = np.abs(np.fft.rfft(samples * np.hanning(len(samples))))
    hz = float(np.fft.rfftfreq(len(samples), 1 / 48000)[int(np.argmax(spectrum))])
    return hz, float(np.sqrt(np.mean(samples ** 2)))


async def keep_alive(worker: Worker, body: dict, stop: asyncio.Event) -> None:
    while not stop.is_set():
        try:
            await worker.call("POST", "/api/source", body)
        except ApiError:
            pass
        await asyncio.sleep(3)


async def main() -> None:
    await host.call("POST", "/api/reset")

    lease = await relay.call("POST", "/api/lease", {"relayId": "test-relay-a"})
    check("relay A gets the lease", lease["granted"])
    other = await relay.call("POST", "/api/lease", {"relayId": "test-relay-b"})
    check("relay B is refused while A holds it", not other["granted"] and other["holder"] == "test-relay-a")

    try:
        await listen.call("POST", "/api/sfu/sessions/new")
        session = (await listen.call("POST", "/api/sfu/sessions/new"))["sessionId"]
        await listen.call("POST", f"/api/sfu/sessions/{session}/tracks/new",
                          {"tracks": [{"location": "local", "mid": "0", "trackName": "app-x"}]})
        check("listener key cannot publish", False)
    except ApiError as error:
        check("listener key cannot publish", error.status == 403)

    # Host goes live from "phone 1" at 440 Hz.
    app_pc, app_session = await publish(host, ToneTrack(440), "app-phone1")
    started_1 = int(time.time() * 1000)
    app_body = {"source": "app", "sessionId": app_session, "trackName": "app-phone1", "startedAt": started_1, "by": "phone1"}
    stop_app = asyncio.Event()
    app_beat = asyncio.ensure_future(keep_alive(host, app_body, stop_app))
    await asyncio.sleep(2)
    state = await listen.call("GET", "/api/state")
    check("going live from the app starts the session", state["session"]["state"] == "live")
    check("the app is on air", state["active"]["source"] == "app")
    hz, rms = await hear()
    check("listener hears the app (440 Hz)", abs(hz - 440) < 15 and rms > 500, f"{hz:.0f} Hz rms {rms:.0f}")

    # The relay hears someone in the Paltalk room (660 Hz) while the app is live.
    pal_pc, pal_session = await publish(relay, ToneTrack(660), "paltalk-test-relay-a")
    pal_body = {"source": "paltalk", "sessionId": pal_session, "trackName": "paltalk-test-relay-a", "relayId": "test-relay-a"}
    stop_pal = asyncio.Event()
    pal_beat = asyncio.ensure_future(keep_alive(relay, pal_body, stop_pal))
    lease_stop = asyncio.Event()

    async def hold_lease() -> None:
        while not lease_stop.is_set():
            await relay.call("POST", "/api/lease", {"relayId": "test-relay-a"})
            await asyncio.sleep(5)

    lease_task = asyncio.ensure_future(hold_lease())
    await asyncio.sleep(2)
    state = await listen.call("GET", "/api/state")
    check("the app keeps the air over Paltalk", state["active"]["source"] == "app")

    try:
        await relay.call("POST", "/api/source", {**pal_body, "relayId": "test-relay-b"})
        check("a relay without the lease cannot publish Paltalk", False)
    except ApiError as error:
        check("a relay without the lease cannot publish Paltalk", error.status == 409)

    # Hazrat Ji moves to "phone 2": the newer device takes over, phone 1 is told to stop.
    app2_pc, app2_session = await publish(host, ToneTrack(880), "app-phone2")
    app2_body = {"source": "app", "sessionId": app2_session, "trackName": "app-phone2", "startedAt": int(time.time() * 1000), "by": "phone2"}
    await host.call("POST", "/api/source", app2_body)
    try:
        await host.call("POST", "/api/source", app_body)
        check("the older device is superseded", False)
    except ApiError as error:
        check("the older device is superseded", error.status == 409 and error.data.get("superseded"))
    stop_app.set()
    await app_beat
    await app_pc.close()
    stop_app2 = asyncio.Event()
    app2_beat = asyncio.ensure_future(keep_alive(host, app2_body, stop_app2))
    await asyncio.sleep(2)
    hz, rms = await hear()
    check("listener follows the new device (880 Hz)", abs(hz - 880) < 15 and rms > 500, f"{hz:.0f} Hz rms {rms:.0f}")

    # Hazrat Ji leaves the app and carries on in Paltalk.
    await host.call("POST", "/api/source", {"source": "app", "sessionId": app2_session, "live": False})
    stop_app2.set()
    await app2_beat
    await app2_pc.close()
    await asyncio.sleep(2)
    state = await listen.call("GET", "/api/state")
    check("Paltalk takes the air when the app stops", state["active"]["source"] == "paltalk")
    hz, rms = await hear()
    check("listener hears the Paltalk room (660 Hz)", abs(hz - 660) < 15 and rms > 500, f"{hz:.0f} Hz rms {rms:.0f}")

    # Stage cues: one pipeline, duplicates folded.
    first = await host.call("POST", "/api/stage", {"stage": "1st Latifa", "origin": "app"})
    again = await relay.call("POST", "/api/stage", {"stage": "1st latifa", "origin": "paltalk"})
    check("a stage cue is recorded", first.get("event", {}).get("seq") == 1)
    check("the same cue from Paltalk is folded as a duplicate", again.get("duplicate") is True)
    second = await relay.call("POST", "/api/stage", {"stage": "2nd", "origin": "paltalk"})
    check("a new cue from Paltalk is recorded", second.get("event", {}).get("origin") == "paltalk")

    try:
        await relay.call("POST", "/api/session", {"action": "end"})
        check("the relay cannot end the session", False)
    except ApiError as error:
        check("the relay cannot end the session", error.status == 403)
    ended = await host.call("POST", "/api/session", {"action": "end"})
    check("an admin ends the session and nothing stays on air", ended["session"]["state"] == "ended" and ended["active"]["source"] is None)

    stop_pal.set()
    lease_stop.set()
    await asyncio.gather(pal_beat, lease_task)
    await pal_pc.close()
    await relay.call("POST", "/api/lease", {"relayId": "test-relay-a", "release": True})
    await host.call("POST", "/api/reset")
    print(f"\n{len(failures)} failure(s)" if failures else "\nall checks passed")


asyncio.run(main())
sys.exit(1 if failures else 0)
