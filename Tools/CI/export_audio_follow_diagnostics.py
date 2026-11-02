"""Export only opt-in playback telemetry, including after a failed UI tour."""
import json
from pathlib import Path
import shutil
import subprocess

result = subprocess.run(["xcrun", "simctl", "list", "devices", "booted", "-j"], capture_output=True, text=True)
if result.returncode == 0:
    devices = json.loads(result.stdout).get("devices", {})
    for group in devices.values():
        for device in group:
            container = subprocess.run(["xcrun", "simctl", "get_app_container", device["udid"], "us.naqshbaniaowaisiah", "data"], capture_output=True, text=True)
            if container.returncode != 0:
                continue
            source = Path(container.stdout.strip()) / "Documents/audio-follow-audit.jsonl"
            if source.is_file():
                target = Path("build/screens") / ("audio-follow-" + device["udid"] + ".jsonl")
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
                print("Exported playback telemetry:", target.name)
