#!/usr/bin/env python3
"""Hiss as an audible event: runs of noise-like frames (flat 1.5-9 kHz spectrum,
no voice harmonics, well under the voice) of 80 ms or more. Each run is placed:
start of file, end of file, before digital silence, or between words.

    hiss3.py <out.json> <rate> @list
"""
import json
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np


def scan(arg):
    path, rate = arg
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(rate), "-"],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.float32)
    W = int(rate * .02)
    n = len(x) // W
    if n < 10:
        return {"file": path, "runs": [], "seconds": len(x) / rate}
    fr = x[:n * W].reshape(n, W)
    w = np.hanning(W)
    P = np.abs(np.fft.rfft(fr * w, axis=1)) ** 2 / (w ** 2).sum() / W * 2
    f = np.fft.rfftfreq(W, 1 / rate)
    band = (f >= 1500) & (f < 9000)
    S = P[:, band] + 1e-16
    flat = np.exp(np.log(S).mean(1)) / S.mean(1)
    lvl = 10 * np.log10((fr ** 2).mean(1) + 1e-14)
    lo = P[:, (f >= 100) & (f < 1500)].sum(1) + 1e-16
    hi = S.sum(1)
    loud = lvl[lvl > -60]
    ref = float(np.percentile(loud, 70)) if len(loud) else -40
    noisy = (flat > .3) & (lvl > -72) & (lvl < ref - 10) & (10 * np.log10(hi / lo) > -6)
    dig = lvl < -80
    runs = []
    i = 0
    while i < n:
        if noisy[i]:
            j = i
            # bridges a single stray frame
            while j + 1 < n and (noisy[j + 1] or (j + 2 < n and noisy[j + 2])):
                j += 1
            if (j - i + 1) * 20 >= 80:
                speech = lvl > ref - 12
                before = np.flatnonzero(speech[:i])
                after = np.flatnonzero(speech[j + 1:])
                where = "start" if not len(before) else "end" if not len(after) else ("to_silence" if dig[min(j + 1, n - 1)] or dig[min(j + 2, n - 1)] else "between")
                runs.append([round(i * .02, 2), (j - i + 1) * 20, round(float(10 * np.log10((10 ** (lvl[i:j + 1] / 10)).mean())), 1), where])
            i = j + 1
        else:
            i += 1
    return {"file": path, "seconds": round(len(x) / rate, 2), "ref": round(ref, 1), "runs": runs}


if __name__ == "__main__":
    out, rate = sys.argv[1], int(sys.argv[2])
    files = Path(sys.argv[3][1:]).read_text().split()
    with ProcessPoolExecutor(6) as p:
        res = list(p.map(scan, [(f, rate) for f in files], chunksize=8))
    Path(out).write_text(json.dumps(res))
    tot = sum(r["seconds"] for r in res)
    runs = [x for r in res for x in r["runs"]]
    print(len(res), "files", round(tot / 60), "min audio;", len(runs), "noise runs in", sum(1 for r in res if r["runs"]), "files; total", sum(x[1] for x in runs) / 1000, "s")
    if runs:
        a = np.array([[x[1], x[2]] for x in runs])
        print("length ms pct50,90,99,max", np.percentile(a[:, 0], [50, 90, 99, 100]), " level dB pct50,90,99,max", np.percentile(a[:, 1], [50, 90, 99, 100]))
        import collections
        print(collections.Counter(x[3] for x in runs))
    top = sorted(res, key=lambda r: -sum(x[1] for x in r["runs"]))[:15]
    for r in top:
        print(Path(r["file"]).name, r["seconds"], sum(x[1] for x in r["runs"]), r["runs"][:5])
