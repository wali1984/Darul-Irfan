#!/usr/bin/env python3
"""Collect simulator stacks during reader idle/query windows, only for diagnosis.

Sampling adds overhead: do not use this run's heartbeat as a performance baseline.
The UI test's navigation and exact-ayah assertions remain unchanged.
"""
import json
import plistlib
from pathlib import Path
import subprocess
import time


def new_reader_load(devices: Path, since: float) -> bool:
    """Detect the first 142 landing before XCTest's tap/idle marker returns."""
    for source in devices.glob("*/data/Containers/Data/Application/*/Documents/reader-audit-2-142-*.jsonl"):
        try:
            if source.stat().st_mtime < since:
                continue
            metadata = source.parent.parent / ".com.apple.mobile_container_manager.metadata.plist"
            with metadata.open("rb") as stream:
                if plistlib.load(stream).get("MCMMetadataIdentifier") != "us.naqshbaniaowaisiah":
                    continue
            first = json.loads(source.read_text().splitlines()[0])
            if first.get("timestamp", 0) >= since and first.get("requestedAyah") == 142:
                return True
        except (OSError, ValueError, IndexError, plistlib.InvalidFileException):
            continue
    return False


def main():
    log = Path("build/logs/xcodebuild-screens.log")
    stop = Path("build/reader-sampling-stop")
    output = Path("build/reader-profile")
    output.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + 3000
    seen = set()
    started = Path("build/audio-follow-started")
    since = started.stat().st_mtime if started.exists() else time.time()
    devices = Path.home() / "Library/Developer/CoreSimulator/Devices"
    while time.monotonic() < deadline and not stop.exists():
        text = log.read_text(errors="replace") if log.exists() else ""
        markers = ["READER_IDLE_BEGIN", "READER_IDLE_END"]
        if "READER_LOAD_BEGIN" not in seen and new_reader_load(devices, since):
            markers.insert(0, "READER_LOAD_BEGIN")
        for marker in markers:
            if marker in seen or (marker != "READER_LOAD_BEGIN" and marker not in text):
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
        if len(seen) == 3:
            return
        time.sleep(0.5)


if __name__ == "__main__":
    main()
