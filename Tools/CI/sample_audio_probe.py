"""Sample only the opt-in simulator audio probe; never terminate the app."""
import json
from pathlib import Path
import shlex
import subprocess
import time


def is_probe(command: str) -> bool:
    try:
        arguments = shlex.split(command)
    except ValueError:
        return False
    return bool(arguments and arguments[0].endswith("/DarulIrfan.app/DarulIrfan")
                and "--uitesting-audio-transport" in arguments[1:])


def main():
    output = Path("build/screens")
    output.mkdir(parents=True, exist_ok=True)
    stop = Path("build/audio-probe-sampling-stop")
    started = time.monotonic()
    seen = {}
    records = []
    try:
        while not stop.exists() and time.monotonic() - started < 3000:
            found = subprocess.run(["pgrep", "-x", "DarulIrfan"], capture_output=True, text=True, timeout=5)
            for value in found.stdout.split():
                if not value.isdecimal():
                    continue
                pid = int(value)
                command = subprocess.run(["ps", "-p", value, "-o", "command="], capture_output=True, text=True, timeout=5)
                if not is_probe(command.stdout.strip()):
                    continue
                first, count = seen.setdefault(pid, (time.monotonic(), 0))
                if count >= 3 or time.monotonic() - first < 8 + count * 10:
                    continue
                destination = output / f"audio-probe-stack-{pid}-{count + 1}.txt"
                try:
                    result = subprocess.run(["sample", value, "2", "10", "-file", str(destination)],
                                            capture_output=True, timeout=12)
                    records.append({"pid": pid, "sample": count + 1, "exitCode": result.returncode,
                                    "file": destination.name, "captured": destination.exists()})
                except subprocess.TimeoutExpired:
                    records.append({"pid": pid, "sample": count + 1, "timeout": True})
                seen[pid] = (first, count + 1)
            time.sleep(2)
    finally:
        (output / "audio-probe-stack-export.json").write_text(json.dumps(records, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
