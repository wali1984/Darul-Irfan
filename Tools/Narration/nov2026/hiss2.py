#!/usr/bin/env python3
"""Hiss measured where a person hears it (read only; decodes at 44.1 or 24 kHz).

- true pauses: quiet stretches >= 160 ms, 40 ms trimmed each side, with no
  digital silence: level in dBFS, high band (4-12 kHz) share, flatness.
- speech: bands 1-4 kHz (voice), 6-9 kHz (the 'sizzle' band), 9.5-11.5 kHz (above
  the voice: noise only).
- on/off: audible noise that steps straight to digital silence.

    hiss2.py <out.json> <rate> <files...|@list>
"""
import json
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np


def decode(path, rate):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", str(rate), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32)


def dbp(p):
    return 10 * np.log10(p + 1e-14)


def scan(arg):
    path, rate = arg
    x = decode(path, rate)
    W = int(rate * 0.02)
    n = len(x) // W
    if n < 25:
        return {"file": str(path), "short": True}
    fr = x[:n * W].reshape(n, W)
    win = np.hanning(W)
    P = np.abs(np.fft.rfft(fr * win, axis=1)) ** 2 / (win ** 2).sum() / W * 2
    f = np.fft.rfftfreq(W, 1 / rate)
    lvl = dbp((fr ** 2).mean(1))
    def band(a, b):
        return P[:, (f >= a) & (f < b)].sum(1)
    voice, sizzle, above, hf = band(1000, 4000), band(6000, 9000), band(9500, 11500), band(4000, 12000)
    loud = lvl[lvl > -60]
    ref = float(np.percentile(loud, 70)) if len(loud) else -40
    speech = lvl > ref - 18
    dig = lvl < -80
    quiet = ~speech & ~dig
    # runs of quiet
    edges = np.flatnonzero(np.diff(np.concatenate([[0], quiet.astype(int), [0]])))
    mask = np.zeros(n, bool)
    longest = 0
    core = np.zeros(n, bool)
    for a, e in zip(edges[::2], edges[1::2]):
        if e - a >= 8:
            mask[a + 2:e - 2] = True
            longest = max(longest, int(e - a) * 20)
            core[a + 7:e - 3] = True  # well past the word's tail
    out = {"file": str(path), "seconds": round(len(x) / rate, 2), "speech_db": round(ref, 1), "pause_run_ms": longest,
           "pause_ms": int(mask.sum()) * 20, "digital_frac": round(float(dig.mean()), 3)}
    if mask.sum():
        spec = P[mask]
        out["pause_db"] = round(float(dbp((fr[mask] ** 2).mean())), 1)
        out["pause_hf_db"] = round(float(dbp(hf[mask].mean())), 1)
        out["pause_snr"] = round(ref - out["pause_db"], 1)
        s = spec[:, (f >= 2000) & (f < 10000)].mean(0)
        out["pause_flat"] = round(float(np.exp(np.log(s + 1e-14).mean()) / (s.mean() + 1e-14)), 3)
    if core.sum() >= 2:
        out["core_db"] = round(float(dbp((fr[core] ** 2).mean())), 1)
        out["core_hf_db"] = round(float(dbp(hf[core].mean())), 1)
    if speech.sum():
        out["sizzle_rel"] = round(float(dbp(sizzle[speech].mean()) - dbp(voice[speech].mean())), 1)
        out["above_rel"] = round(float(dbp(above[speech].mean()) - dbp(voice[speech].mean())), 1)
    # audible noise stepping to digital silence within one frame
    steps = [float(lvl[i]) for i in range(1, n) if (dig[i] and not dig[i - 1]) or (dig[i - 1] and not dig[i])]
    steps = [max(lvl[i - 1], lvl[i]) for i in range(1, n) if dig[i] != dig[i - 1]]
    out["onoff_n"] = len(steps)
    out["onoff_db"] = round(float(max(steps)), 1) if steps else None
    return out


def main():
    out, rate = sys.argv[1], int(sys.argv[2])
    files = []
    for a in sys.argv[3:]:
        files += Path(a[1:]).read_text().split() if a.startswith("@") else [a]
    with ProcessPoolExecutor(6) as pool:
        res = list(pool.map(scan, [(f, rate) for f in files], chunksize=8))
    Path(out).write_text(json.dumps(res))
    ok = [r for r in res if "pause_db" in r]
    for k in ("speech_db", "pause_db", "pause_snr", "pause_hf_db", "core_db", "core_hf_db", "pause_flat", "sizzle_rel", "above_rel", "onoff_db", "pause_run_ms"):
        v = np.array([r[k] for r in ok if r.get(k) is not None], float)
        if len(v):
            print(k, np.round(np.percentile(v, [1, 25, 50, 75, 95, 99]), 2))
    print(len(res), "files,", len(ok), "with pauses")


if __name__ == "__main__":
    main()
