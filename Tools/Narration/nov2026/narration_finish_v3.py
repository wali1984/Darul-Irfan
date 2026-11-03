#!/usr/bin/env python3
"""November 2026 finishing chain for the Urdu narration.

Measured on all 6,236 translation files (nov-fixes/scan):
- Pauses still sit near -53 dB, 26 dB under the voice, and step into digital
  silence: the voice's reference clip has a -48 dB floor that Higgs copies, and
  the old filter (afftdn + a gate at 0.012) took only 5 dB off.
- The 6-9 kHz band runs 4 dB hotter than the real reader in the reference
  (-12.6 vs -16.5 dB against 1-4 kHz) and up to 7 dB more in the worst files:
  the metallic hiss heard on the voice itself. No filter touched it.
- The old cut at -38 dB, 11 dB under the voice, can clip a soft last syllable.

Here: one gentle shelf for the hot band, a de-esser for its worst moments, then a
level-following expander that lowers pauses only (lookahead so no consonant
start is touched, release so word tails ring out). The ends are cut well below
the voice and fade into the silence, so nothing switches on or off.

    narration_finish_v3.py <in> <out.mp3>
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np

RATE = 24000
LEAD, TAIL = 0.05, 0.40
SHELF = "highshelf=f=6200:t=q:w=0.7:g=-4"
DEESS = "deesser=i=0.35:m=0.5:f=0.5:s=o"
HOP = 120                     # 5 ms
OPEN_BELOW_VOICE = 17.0       # the voice for sure: above this far under its level
CLOSED_DB = -32.0             # how far a pause is lowered
LOOKAHEAD, HOLD, RELEASE = 0.035, 0.060, 0.070
ATTACK = 0.012
END_BELOW_VOICE = 24.0        # file ends: cut this far under the voice
KEEP_BEFORE, KEEP_AFTER = 0.04, 0.22
FADE_IN, FADE_OUT = 0.015, 0.16


def decode(path: Path) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", str(RATE), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32)


def filtered(audio: np.ndarray, chain: str) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                          "-af", chain, "-f", "f32le", "-"], input=audio.astype(np.float32).tobytes(),
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32)


def levels(audio: np.ndarray) -> np.ndarray:
    frames = len(audio) // HOP
    return 20 * np.log10(np.sqrt(np.mean(audio[:frames * HOP].reshape(frames, HOP) ** 2, axis=1)) + 1e-9)


def voice_level(level: np.ndarray) -> float:
    loud = level[level > -60]
    return float(np.percentile(loud, 70)) if len(loud) else -30.0


def expand(audio: np.ndarray) -> np.ndarray:
    """Lower the pauses; the voice and its edges pass unchanged."""
    level = levels(audio)
    if not len(level):
        return audio
    voice = level > voice_level(level) - OPEN_BELOW_VOICE
    # Open early enough for the consonant, stay open for the word's tail.
    keep = voice.copy()
    before, after = int(LOOKAHEAD * RATE / HOP), int(HOLD * RATE / HOP)
    for i in np.flatnonzero(voice):
        keep[max(0, i - before):i + after + 1] = True
    closed = 10 ** (CLOSED_DB / 20)
    target = np.where(keep, 1.0, closed)
    # Attack and release ramps in dB, then sample-rate gain.
    gain = target.copy()
    up, down = HOP / (ATTACK * RATE), HOP / (RELEASE * RATE)
    db = 20 * np.log10(gain)
    for i in range(1, len(db)):
        step = CLOSED_DB * -1 * down
        if db[i] < db[i - 1] - step:
            db[i] = db[i - 1] - step
    gain = 10 ** (db / 20)
    per_sample = np.interp(np.arange(len(audio)), (np.arange(len(gain)) + 0.5) * HOP, gain)
    return (audio * per_sample).astype(np.float32)


BREATH_MS, BREATH_DUCK_DB = 120, -12.0


def duck_breaths(audio: np.ndarray, apply_to: np.ndarray | None = None) -> tuple[np.ndarray, int]:
    """Audible breaths and hiss bursts: 120 ms or more of noise-like sound (flat
    1.5-9 kHz spectrum, no voice harmonics, at least 10 dB under the voice)
    next to a pause or trailing off. Measured: 528 such bursts in 502 of 6,236 rev-2 files,
    about -41 dB; most are the voice drawing breath. They are lowered 12 dB,
    not removed, so a breathy consonant mistaken for one is still heard.
    Found on the unfiltered take (the shelf changes the spectrum it reads),
    applied to `apply_to`."""
    target = audio if apply_to is None else apply_to
    W, H = int(RATE * .02), int(RATE * .01)
    n = (len(audio) - W) // H
    if n < 10:
        return audio, 0
    idx = np.arange(W)[None, :] + H * np.arange(n)[:, None]
    fr = audio[idx]
    w = np.hanning(W)
    P = np.abs(np.fft.rfft(fr * w, axis=1)) ** 2 + 1e-16
    f = np.fft.rfftfreq(W, 1 / RATE)
    S = P[:, (f >= 1500) & (f < 9000)]
    flat = np.exp(np.log(S).mean(1)) / S.mean(1)
    lvl = 10 * np.log10((fr ** 2).mean(1) + 1e-14)
    tilt = 10 * np.log10(S.sum(1) / P[:, (f >= 100) & (f < 1500)].sum(1))
    loud = lvl[lvl > -60]
    ref = float(np.percentile(loud, 70)) if len(loud) else -40
    noisy = (flat > .3) & (lvl > -72) & (lvl < ref - 10) & (tilt > -6)
    gain = np.ones(n)
    count, i = 0, 0
    while i < n:
        if not noisy[i]:
            i += 1
            continue
        j = i
        while j + 1 < n and (noisy[j + 1] or (j + 2 < n and noisy[j + 2])):
            j += 1
        level = lvl[i:j + 1].mean()
        # Next to something that is not voice on one side (a pause, or the
        # breath trailing off): a consonant inside a word has voice both sides.
        before = lvl[max(0, i - 5):i]
        after = lvl[j + 1:j + 6]
        unvoiced_side = (len(before) and before.min() < ref - 12) or (len(after) and after.min() < ref - 12) or not len(before) or not len(after)
        if (j - i + 1) * 10 >= BREATH_MS and unvoiced_side:
            gain[i:j + 1] = 10 ** (BREATH_DUCK_DB / 20)
            count += 1
        i = j + 1
    if not count:
        return target, 0
    # 15 ms ramps
    k = 3
    smooth = np.convolve(np.pad(gain, k, mode="edge"), np.ones(2 * k + 1) / (2 * k + 1), mode="valid")
    per_sample = np.interp(np.arange(len(target)), np.arange(n) * H + W / 2, smooth)
    return (target * per_sample).astype(np.float32), count


def finish(audio: np.ndarray, shelf: bool = True) -> np.ndarray:
    shaped = filtered(audio, f"{SHELF},{DEESS}") if shelf else audio
    audio, _ = duck_breaths(audio, shaped[:len(audio)] if len(shaped) >= len(audio) else np.pad(shaped, (0, len(audio) - len(shaped))))
    audio = expand(audio)
    level = levels(audio)
    loud = np.flatnonzero(level > voice_level(level) - END_BELOW_VOICE)
    if not len(loud):
        return audio
    start = max(0, loud[0] * HOP - int(RATE * KEEP_BEFORE))
    end = min(len(audio), (loud[-1] + 1) * HOP + int(RATE * KEEP_AFTER))
    body = audio[start:end].copy()
    n_in, n_out = min(len(body), int(RATE * FADE_IN)), min(len(body), int(RATE * FADE_OUT))
    body[:n_in] *= np.linspace(0.0, 1.0, n_in, dtype=np.float32) ** 2
    body[-n_out:] *= np.linspace(1.0, 0.0, n_out, dtype=np.float32) ** 2
    return np.concatenate([np.zeros(int(RATE * LEAD), np.float32), body, np.zeros(int(RATE * TAIL), np.float32)])


def encode(audio: np.ndarray, target: Path) -> None:
    temporary = target.with_name(target.stem + ".part.mp3")
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                    "-b:a", "64k", str(temporary)], input=audio.astype(np.float32).tobytes(), check=True)
    temporary.replace(target)


if __name__ == "__main__":
    encode(finish(decode(Path(sys.argv[1]))), Path(sys.argv[2]))
