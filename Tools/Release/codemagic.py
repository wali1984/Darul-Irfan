"""Codemagic from this PC: build status, start a workflow, follow a build, and
read the log of whatever step failed.

The API token is read from CODEMAGIC_API_TOKEN, or from `codemagic.md` one
folder above this repository (outside git, a line "API: <token>"). It is
never printed.

usage:
  codemagic.py status [count]                 recent Darul-Irfan builds
  codemagic.py start <workflow> [branch]      e.g. start ios-verify main
  codemagic.py watch <build-id>               poll until it finishes
  codemagic.py log <build-id> [lines]         tail of each failed step's log
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.codemagic.io"
APP_ID = "6a502f90353ca0edc6c3fcb8"  # wali1984/Darul-Irfan
WORKFLOWS = {"ios-verify", "ios-testflight", "hadith-ingest"}
FINAL = {"finished", "failed", "canceled", "timeout", "skipped"}
TOKEN_FILE = Path(__file__).resolve().parents[3] / "codemagic.md"


def token() -> str:
    value = os.environ.get("CODEMAGIC_API_TOKEN", "").strip()
    if not value and TOKEN_FILE.exists():
        match = re.search(r"API:\s*(\S+)", TOKEN_FILE.read_text(encoding="utf-8"))
        value = match.group(1) if match else ""
    if not value:
        sys.exit(f"No Codemagic token: set CODEMAGIC_API_TOKEN or add 'API: <token>' to {TOKEN_FILE}")
    return value


def call(method: str, path: str, body: dict | None = None, raw: bool = False):
    request = urllib.request.Request(
        path if path.startswith("http") else API + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={"x-auth-token": token(), "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read()
    except urllib.error.HTTPError as error:
        sys.exit(f"HTTP {error.code}: {error.read()[:300].decode(errors='replace')}")
    return data.decode("utf-8", errors="replace") if raw else json.loads(data or b"{}")


def line(build: dict) -> str:
    commit = build.get("commit") or {}
    return " | ".join(str(part) for part in (
        build.get("_id"), build.get("fileWorkflowId"), build.get("status"),
        (commit.get("hash") or "")[:7], build.get("tag") or build.get("branch"),
        (build.get("startedAt") or "")[:16], f"#{build.get('index')}",
    ))


def status(count: int = 8) -> None:
    for build in call("GET", f"/builds?appId={APP_ID}").get("builds", [])[:count]:
        print(line(build))


def start(workflow: str, branch: str = "main") -> None:
    if workflow not in WORKFLOWS:
        sys.exit(f"Unknown workflow {workflow}; one of {sorted(WORKFLOWS)}")
    result = call("POST", "/builds", {"appId": APP_ID, "workflowId": workflow, "branch": branch})
    print("started", result.get("buildId"))


def build(build_id: str) -> dict:
    return call("GET", f"/builds/{build_id}").get("build", {})


def watch(build_id: str) -> None:
    last = None
    while True:
        current = build(build_id)
        state = current.get("status")
        if state != last:
            print(time.strftime("%H:%M:%S"), line(current), flush=True)
            last = state
        if state in FINAL:
            log(build_id, 60, only_failed=True)
            return
        time.sleep(30)


def log(build_id: str, lines: int = 80, only_failed: bool = True) -> None:
    for action in build(build_id).get("buildActions", []):
        failed = action.get("status") not in ("success", "skipped", None)
        if only_failed and not failed:
            continue
        print(f"== {action.get('name')} [{action.get('status')}]")
        # The log hangs off the step's sub-actions, not the action itself.
        for url in [action.get("logUrl")] + [sub.get("logUrl") for sub in action.get("subactions") or []]:
            if url:
                text = call("GET", url, raw=True)
                print("\n".join(text.splitlines()[-lines:]))


def main() -> None:
    args = sys.argv[1:]
    sys.stdout.reconfigure(encoding="utf-8")
    if not args or args[0] == "status":
        status(int(args[1]) if len(args) > 1 else 8)
    elif args[0] == "start" and len(args) >= 2:
        start(args[1], args[2] if len(args) > 2 else "main")
    elif args[0] == "watch" and len(args) == 2:
        watch(args[1])
    elif args[0] == "log" and len(args) >= 2:
        log(args[1], int(args[2]) if len(args) > 2 else 80)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
