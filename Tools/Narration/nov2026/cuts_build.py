#!/usr/bin/env python3
"""Corrected ayah cut points for the Afasy recordings, from the audio itself.

For each boundary the real pause next to the table's boundary is found on a
fine (5 ms) envelope:
  voice end E, next voice onset O.  stop = E + 60% of the pause (capped so at
  least 40 ms remains before O), start of next = max(stop, O - 90 ms).
A boundary whose nearest pause is farther than --window, or which has no deep
pause, keeps the table's value and is listed for the alignment check.

Also simulates what a person hears: per ayah in "both" mode, how much of the
next ayah leaks in, how much of this ayah's voice is cut, how much of the next
ayah's start is cut, for policies (stop = to-G, start = from-L), table vs new.

    cuts_build.py arabic scan/cuts.json
"""
import json
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np

R, HOP = 16000, 80  # 5 ms
ROOT = Path(sys.argv[1])
T = json.load(open(ROOT / "timings.json", encoding="utf-8"))["surahs"]
WINDOW = 150      # ms: only a pause this near the table is trusted without alignment
MINGAP = 30       # ms
OVERRIDES = {}
OV = Path("scan/cut_overrides.json")
if OV.exists():
    OVERRIDES = json.load(open(OV))


def env(key):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(ROOT / f"{key}.mp3"), "-f", "f32le", "-ac", "1", "-ar", str(R), "-"],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.float32)
    n = len(x) // HOP
    return 20 * np.log10(np.sqrt((x[:n * HOP].reshape(n, HOP) ** 2).mean(1)) + 1e-9)


def pauses(lvl, center, reach):
    lo, hi = max(0, center - reach), min(len(lvl), center + reach)
    seg = lvl[lo:hi]
    if len(seg) < 20:
        return [], None
    peak = np.percentile(seg, 90)
    th = max(seg.min() + 6, peak - 30)
    q = seg < th
    e = np.flatnonzero(np.diff(np.concatenate([[0], q.astype(int), [0]])))
    return [(int(a) + lo, int(b) + lo, float(peak - seg[a:b].mean())) for a, b in zip(e[::2], e[1::2]) if (b - a) * 5 >= MINGAP], float(peak)


def run(key):
    lvl = env(key)
    vs = T[key]["verses"]
    rows = []
    for i, v in enumerate(vs[:-1]):
        nxt = vs[i + 1]
        b = int(v["toMs"] / 5)
        over = OVERRIDES.get(f"{key}:{v['ayah']}")
        center = int(over / 5) if over else b
        ps, peak = pauses(lvl, center, int(3000 / 5))
        row = {"s": int(key), "a": v["ayah"], "to": v["toMs"], "next": nxt["fromMs"], "stop": v["toMs"], "start": nxt["fromMs"], "status": "kept"}
        if ps:
            def dist(p):
                if over:
                    # the pause that ends nearest the predicted start of the next ayah
                    return abs(p[1] - center)
                return 0 if p[0] <= center < p[1] else min(abs(center - p[0]), abs(center - p[1]))
            p = min(ps, key=dist)
            d = dist(p) * 5
            row.update(voice_end=p[0] * 5, voice_on=p[1] * 5, depth=round(p[2], 1), dist=d)
            if (d <= WINDOW or (over and d <= 500)) and p[2] >= 20:
                E, O = p[0] * 5, p[1] * 5
                gap = O - E
                stop = E + min(int(gap * .6), max(gap - 40, 0))
                start = max(stop, O - 90)
                row.update(stop=stop, start=start, status="fixed" if not over else "aligned")
            else:
                row["status"] = "nopause" if d > WINDOW or p[2] < 20 else "kept"
        rows.append(row)
    return rows


def simulate(rows, stop_key, start_key, G, L):
    leak = cut = headcut = 0
    leaks, cuts, heads = [], [], []
    for r in rows:
        if "voice_end" not in r or r["dist"] > 150:
            continue
        stop = r[stop_key] - G
        start = r[start_key] - L
        E, O = r["voice_end"], r["voice_on"]
        if stop > O:
            leak += 1
            leaks.append(stop - O)
        if stop < E - 20:
            cut += 1
            cuts.append(E - stop)
        if start > O + 10:
            headcut += 1
            heads.append(start - O)
    n = len([r for r in rows if "voice_end" in r and r["dist"] <= 150])
    m = lambda a: int(np.median(a)) if a else 0
    return f"G={G:3d} L={L:3d}  {stop_key:5s}/{start_key:5s}  of {n}: next voice heard {leak} (med {m(leaks)} ms); end cut {cut} (med {m(cuts)} ms); start cut {headcut} (med {m(heads)} ms)"


if __name__ == "__main__":
    keys = sorted(T, key=int)
    with ProcessPoolExecutor(6) as pool:
        res = [r for rows in pool.map(run, keys) for r in rows]
    Path(sys.argv[2]).write_text(json.dumps(res))
    import collections
    print(collections.Counter(r["status"] for r in res))
    for G, L in [(0, 0), (25, 0), (40, 0), (40, 40), (60, 40), (60, 60), (80, 80)]:
        print("table:", simulate(res, "to", "next", G, L))
    for G in (0, 40, 60, 100):
        print("cuts :", simulate(res, "stop", "start", G, 0))
    by = collections.Counter(r["s"] for r in res if r["status"] == "nopause")
    print("no pause by surah", by.most_common(12))
    big = [(r["s"], r["a"], r["dist"]) for r in res if r.get("dist", 0) > 150 and r["status"] != "nopause"]
    print("table >150 ms off the pause", len(big), collections.Counter(b[0] for b in big).most_common(12))
