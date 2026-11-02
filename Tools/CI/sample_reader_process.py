#!/usr/bin/env python3
"""Collect simulator stacks during reader idle/query windows, only for diagnosis.

Sampling adds overhead: do not use this run's heartbeat as a performance baseline.
The UI test's navigation and exact-ayah assertions remain unchanged.
"""
import json
from pathlib import Path
import subprocess
import time


def main():
    log = Path("build/logs/xcodebuild-screens.log")
    stop = Path("build/reader-sampling-stop")
    output = Path("build/reader-profile")
    output.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + 3000
    seen = set()
    while time.monotonic() < deadline and not stop.exists():
        text = log.read_text(errors="replace") if log.exists() else ""
        for marker in ("READER_IDLE_BEGIN", "READER_IDLE_END"):
            if marker in seen or marker not in text:
                continue
            seen.add(marker)
            found = subprocess.run(["pgrep", "-x", "DarulIrfan"], capture_output=True, text=True)
            for pid in found.stdout.split():
                if not pid.isdigit():
                    continue
                target = output / f"{marker.lower()}-{pid}.txt"
                try:
                    result = subprocess.run(
                        ["sample", pid, "10", "10", "-file", str(target)],
                        capture_output=True, text=True, timeout=20,
                    )
                    print(json.dumps({"marker": marker, "pid": pid, "exit": result.returncode,
                                      "stderr": result.stderr[-1000:]}), flush=True)
                except subprocess.TimeoutExpired:
                    print(json.dumps({"marker": marker, "pid": pid, "error": "sample timed out"}), flush=True)
        if len(seen) == 2:
            return
        time.sleep(0.5)


if __name__ == "__main__":
    main()
