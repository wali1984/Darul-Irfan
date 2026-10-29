"""Hourly watch for what the v1.12.0 release still waits on (owner, 2026-10-29:
"deploy tag release all what is completed. update again after urdu narration
and another one on completion of tafsir").

Task Scheduler runs this every 10 minutes (task "Darul Irfan - release watch").
Each run:
  1. Urdu narration: once amd has re-recorded and published the corrected
     translation narration (redo_corrections.sh), tell the owner.
  2. iOS v1.12.0: Codemagic refuses builds until billing is enabled (HTTP 402)
     or the free minutes renew on the 1st of the month. When it accepts one,
     build ios-testflight (it runs the unit tests and content gates before it
     signs anything), put the build in front of the testers, then tell the
     owner. A failed build stops here and says so: the code needs a person.
     Skipped while the Akram-ut-Tafaseer release is building from main, which
     carries v1.12.0 too.
  3. The update banner: the newest build Apple has passed for the external
     testers is named to the apps (testflight.py announce), so a TestFlight
     copy on an older build offers the newer one on Today. This is the step
     that keeps the watch running after the release.
Each event is announced once (notify.py: a Windows notification and a line in
automation/UPDATES.md). Akram-ut-Tafaseer announces itself
(akram_tafaseer_release.py).

    python Tools/Release/release_watch.py
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
IOS = HERE.parents[1]
ROOT = IOS.parent
sys.path.insert(0, str(HERE))
import codemagic  # noqa: E402
import testflight  # noqa: E402
from notify import notify  # noqa: E402

WORK = ROOT / "automation" / "release-watch"
STATE = WORK / "state.json"
AKRAM_STATE = ROOT / "automation" / "akram-tafaseer" / "state.json"
NOTES = ROOT / "audit-2026-10-29" / "TESTFLIGHT-WHAT-TO-TEST-v1.12.txt"
SSH = Path(r"C:\Program Files\Git\usr\bin\ssh.exe")
ASKPASS = ROOT / "automation" / "askpass.sh"
AMD = "wali@10.10.100.100"
SERVER = "https://darul-irfan-platform.wajidmahmoodali1984-e23.workers.dev"   # the apps' OfficialPlatformBaseURL
VOICES = "/mnt/sata1tb/di-voices"


def load() -> dict:
    return json.loads(STATE.read_text(encoding="utf-8")) if STATE.exists() else {}


def save(state: dict) -> None:
    WORK.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=1), encoding="utf-8")


def amd(command: str) -> str:
    env = dict(os.environ, PATH=str(SSH.parent) + os.pathsep + os.environ.get("PATH", ""),
               SSH_ASKPASS=str(ASKPASS), SSH_ASKPASS_REQUIRE="force", DISPLAY=":0")
    result = subprocess.run([str(SSH), "-o", "ConnectTimeout=20", AMD, command], env=env,
                            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
    if result.returncode == 255:  # ssh itself failed: amd unreachable, not a stopped run
        raise RuntimeError("ssh to amd failed: " + result.stderr.strip()[:200])
    return result.stdout


def narration(state: dict) -> None:
    if state.get("narration_done"):
        return
    out = amd(f"grep -E '2020-print narration finished|HALTED present' {VOICES}/redo_cycle.log | tail -1; "
              f"pgrep -f '[r]edo_corrections.sh' >/dev/null && echo RUNNING")
    if "2020-print narration finished" in out:
        line = next(l for l in out.splitlines() if "2020-print narration finished" in l)
        held = line.split(";", 1)[1].strip() if ";" in line else ""
        notify("Urdu narration published",
               "The corrected Urdu translation narration is re-recorded, checked word by word and live"
               + (f" ({held})." if held else "."))
        state["narration_done"] = True
    elif "HALTED present" in out or "RUNNING" not in out:
        if not state.get("narration_stopped_noted"):
            notify("Urdu narration needs a look",
                   "The corrected-narration run on amd stopped before publishing; see "
                   f"{VOICES}/redo_cycle.log. Publishing stays held.")
            state["narration_stopped_noted"] = True


def start(workflow: str) -> str | None:
    """Start a Codemagic workflow on main; None while billing refuses (HTTP 402)."""
    request = urllib.request.Request(
        codemagic.API + "/builds", method="POST",
        data=json.dumps({"appId": codemagic.APP_ID, "workflowId": workflow, "branch": "main"}).encode(),
        headers={"x-auth-token": codemagic.token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read() or b"{}").get("buildId")
    except urllib.error.HTTPError as error:
        if error.code == 402:
            return None
        raise


def wait(build_id: str) -> str:
    while True:
        status = codemagic.build(build_id).get("status")
        if status in codemagic.FINAL:
            return status
        time.sleep(60)


def ios(state: dict) -> None:
    if state.get("ios_done") or state.get("ios_failed"):
        return
    akram = json.loads(AKRAM_STATE.read_text(encoding="utf-8")) if AKRAM_STATE.exists() else {}
    if "committed" in akram.get("done", []) and "testflight" not in akram.get("done", []):
        return  # that release builds main, which carries v1.12.0
    if not state.get("testflight_build"):
        started = datetime.now(timezone.utc)
        build = start("ios-testflight")
        if build is None:
            if not state.get("billing_noted"):
                notify("iOS release waiting on Codemagic billing",
                       "Codemagic refuses builds until billing is enabled or the free minutes renew on the 1st. "
                       "v1.12.0 goes to TestFlight by itself within 10 minutes after either.")
                state["billing_noted"] = True
            return
        state["testflight_build"], state["testflight_started"] = build, started.isoformat()
        save(state)
        notify("iOS 1.12 is building", f"Codemagic accepted the TestFlight build ({build}). The testers get it "
                                       "once it passes its tests and Apple has processed it.")
    status = wait(state["testflight_build"])
    if status != "finished":
        notify("iOS v1.12.0 build failed",
               f"Codemagic ios-testflight ended '{status}' (build {state['testflight_build']}); the code needs a "
               "fix before TestFlight. Nothing was released.")
        state["ios_failed"] = True
        return
    started = datetime.fromisoformat(state["testflight_started"])
    number = None
    for _ in range(90):
        number = next((b["number"] for b in testflight.newest(5)
                       if datetime.fromisoformat(b["uploaded"]) > started), None)
        if number:
            break
        time.sleep(60)
    if not number:
        return  # tried again next run
    notes = NOTES.read_text(encoding="utf-8").strip() if NOTES.exists() else "Darul Irfan 1.12"
    if testflight.release(number, notes[:3900]) == 0:
        notify("Darul Irfan 1.12 is on TestFlight", f"Build {number} is with the internal testers and submitted to "
                                                       "external review.")
        state["ios_done"] = True


def announce(state: dict) -> None:
    # Nothing is written until the server serves the releases: its deploy
    # waits for the owner's go-ahead.
    if not state.get("releases_route_live"):
        # Cloudflare refuses Python's own user agent (error 1010).
        request = urllib.request.Request(SERVER + "/v1/app/releases", headers={"User-Agent": "DarulIrfan-release-watch"})
        try:
            urllib.request.urlopen(request, timeout=20).close()
        except (urllib.error.URLError, TimeoutError):
            return
        state["releases_route_live"] = True
    number = testflight.announce(known=state.get("announced_build"))
    if number:
        state["announced_build"] = number


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    WORK.mkdir(parents=True, exist_ok=True)
    state = load()
    for step in (narration, ios, announce):
        try:
            step(state)
        except Exception as error:  # noqa: BLE001 - an unattended watch must not die on one step
            with (WORK / "errors.log").open("a", encoding="utf-8") as handle:
                handle.write(f"{datetime.now():%Y-%m-%d %H:%M} {step.__name__}: {error!r}\n")
        save(state)
    return 0


if __name__ == "__main__":
    sys.exit(main())
