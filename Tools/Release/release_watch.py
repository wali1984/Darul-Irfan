"""Hourly watch for what the v1.12.0 release still waits on (owner, 2026-10-29:
"deploy tag release all what is completed. update again after urdu narration
and another one on completion of tafsir").

Task Scheduler runs this every hour (task "Darul Irfan - release watch"). Each
run:
  1. Urdu narration: once amd has re-recorded and published the corrected
     translation narration (redo_corrections.sh), tell the owner.
  2. iOS v1.12.0: Codemagic refuses builds until billing is enabled (HTTP 402).
     When it accepts one, build ios-verify; if that passes, build for
     TestFlight and put the build in front of the testers, then tell the
     owner. A failed verify stops here and says so: the code needs a person.
     Skipped while the Akram-ut-Tafaseer release is building from main, which
     carries v1.12.0 too.
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
    if not state.get("verify_build"):
        build = start("ios-verify")
        if build is None:
            if not state.get("billing_noted"):
                notify("iOS release waiting on Codemagic billing",
                       "Codemagic refuses builds until billing is enabled. v1.12.0 goes to TestFlight "
                       "by itself within the hour after it is.")
                state["billing_noted"] = True
            return
        state["verify_build"] = build
        save(state)
    status = wait(state["verify_build"])
    if status != "finished":
        notify("iOS v1.12.0 does not build",
               f"Codemagic ios-verify ended '{status}' (build {state['verify_build']}); the Swift needs a fix "
               "before TestFlight. Nothing was released.")
        state["ios_failed"] = True
        return
    if not state.get("testflight_build"):
        started = datetime.now(timezone.utc)
        build = start("ios-testflight")
        if build is None:
            return
        state["testflight_build"], state["testflight_started"] = build, started.isoformat()
        save(state)
    status = wait(state["testflight_build"])
    if status != "finished":
        notify("iOS TestFlight build failed",
               f"Codemagic ios-testflight ended '{status}' (build {state['testflight_build']}). Nothing was released.")
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
        return  # tried again next hour
    notes = NOTES.read_text(encoding="utf-8").strip() if NOTES.exists() else "Darul Irfan 1.12"
    if testflight.release(number, notes[:3900]) == 0:
        notify("Darul Irfan 1.12 is on TestFlight", f"Build {number} is with the internal testers and submitted to "
                                                       "external review.")
        state["ios_done"] = True


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    WORK.mkdir(parents=True, exist_ok=True)
    state = load()
    for step in (narration, ios):
        try:
            step(state)
        except Exception as error:  # noqa: BLE001 - an unattended watch must not die on one step
            with (WORK / "errors.log").open("a", encoding="utf-8") as handle:
                handle.write(f"{datetime.now():%Y-%m-%d %H:%M} {step.__name__}: {error!r}\n")
        save(state)
    return 0


if __name__ == "__main__":
    sys.exit(main())
