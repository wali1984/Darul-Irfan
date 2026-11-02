"""Record host audio availability for the opt-in simulator transport audit."""
import json
from pathlib import Path
import subprocess
import time
import wave


def capture(arguments, timeout):
    started = time.monotonic()
    try:
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout)
        return {"exitCode": result.returncode, "seconds": round(time.monotonic() - started, 2),
                "stdout": result.stdout, "stderr": result.stderr}
    except subprocess.TimeoutExpired:
        return {"timeout": True, "seconds": round(time.monotonic() - started, 2)}
    except OSError as error:
        return {"error": str(error)}


def main():
    output = Path("build/screens")
    output.mkdir(parents=True, exist_ok=True)
    records = {"hostAudioDevices": capture(["system_profiler", "SPAudioDataType", "-json"], 20)}
    # Compare a real local audio clock outside Simulator. Silence avoids
    # audible output; normal completion should take approximately three seconds.
    probe = output / "host-audio-probe.wav"
    with wave.open(str(probe), "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(8000)
        audio.writeframes(bytes(3 * 8000 * 2))
    records["hostPlayback"] = capture(["afplay", str(probe)], 12)
    probe.unlink(missing_ok=True)
    (output / "audio-host-environment.json").write_text(json.dumps(records, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
