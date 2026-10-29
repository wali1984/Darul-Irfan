#!/usr/bin/env python3
"""The last step for every Urdu narration: a clean, even end, so one ayah runs
into the next like a reader pausing, not like clips stitched together.

The owner heard "a gap and a sound at each ayah end". Measured: the voice
leaves ~0.4 s of faint hiss (about -45 dB) after the last word, then the file
dropped to digital silence for 0.35 s, and the next file started the hiss again
- about a second between ayat with the hiss switching off and on. Here the
steady hiss is taken out of the whole file (so every pause is quiet, inside an
ayah and between ayat), the file is cut to the speech, and it gets the same
short lead-in and a natural pause after.

    narration_finish.py <in.mp3> <out.mp3>     one file
    narration_finish.py --all <kind>          every file of that kind, in place
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np

RATE = 24000
LEAD, TAIL = 0.05, 0.40          # silence before the first word, pause after the last
KEEP_BEFORE, KEEP_AFTER = 0.03, 0.15
FADE_IN, FADE_OUT = 0.02, 0.10
# The steady hiss is filtered out, and a gentle gate quietens what is left in
# the pauses (speech is far above it and is not touched).
DENOISE = "afftdn=nr=20:nf=-44:tn=1,agate=threshold=0.012:ratio=3:attack=5:release=180:range=0.06"
# Below this a frame is pause, breath or hiss, not speech (measured: speech
# frames -20 to -35 dB, the tail after the last word -39 to -48 dB).
SPEECH_DB = -38.0


def decode(path: Path) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", str(RATE), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32)


def denoise(audio: np.ndarray) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                          "-af", DENOISE, "-f", "f32le", "-"], input=audio.astype(np.float32).tobytes(),
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32)


def finish(audio: np.ndarray) -> np.ndarray:
    """Hiss removed, cut to the speech, faded, with the standard lead and pause."""
    audio = denoise(audio)
    window = int(RATE * 0.02)
    frames = len(audio) // window
    if frames < 3:
        return audio
    level = 20 * np.log10(np.sqrt(np.mean(audio[:frames * window].reshape(frames, window) ** 2, axis=1)) + 1e-9)
    loud = np.flatnonzero(level > SPEECH_DB)
    if not len(loud):
        return audio
    start = max(0, loud[0] * window - int(RATE * KEEP_BEFORE))
    end = min(len(audio), (loud[-1] + 1) * window + int(RATE * KEEP_AFTER))
    body = audio[start:end].copy()
    n_in, n_out = int(RATE * FADE_IN), min(len(body), int(RATE * FADE_OUT))
    body[:n_in] *= np.linspace(0.0, 1.0, n_in, dtype=np.float32)
    body[-n_out:] *= np.linspace(1.0, 0.0, n_out, dtype=np.float32)
    return np.concatenate([np.zeros(int(RATE * LEAD), np.float32), body, np.zeros(int(RATE * TAIL), np.float32)])


def encode(audio: np.ndarray, target: Path) -> None:
    temporary = target.with_name(target.stem + ".part.mp3")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                    "-b:a", "64k", str(temporary)], input=audio.astype(np.float32).tobytes(), check=True)
    temporary.replace(target)


def main() -> int:
    if sys.argv[1] == "--all":
        from concurrent.futures import ThreadPoolExecutor
        root = Path("/mnt/sata1tb/di-voices/quran-higgs")
        done = root.parent / f"finished_{sys.argv[2]}.txt"
        finished = set(done.read_text().split()) if done.exists() else set()
        files = [p for p in sorted(root.glob(f"*/{sys.argv[2]}/*.mp3")) if str(p) not in finished and ".part" not in p.name]

        def one(path: Path) -> str:
            encode(finish(decode(path)), path)
            return str(path)
        with ThreadPoolExecutor(max_workers=12) as pool, done.open("a") as log:
            for count, name in enumerate(pool.map(one, files), 1):
                log.write(name + "\n")
                if count % 500 == 0:
                    print(f"{count}/{len(files)} finished", flush=True)
        print(f"all {len(files)} finished", flush=True)
        return 0
    encode(finish(decode(Path(sys.argv[1]))), Path(sys.argv[2]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
