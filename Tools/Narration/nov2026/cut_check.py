#!/usr/bin/env python3
"""Whisper check of ayah clips, old table versus the measured cuts: does a clip
hold its ayah's first and last words, and none of the next ayah's?

Surahs 14, 37, 60, 78, 82 in full, plus 150 random ayat elsewhere as controls.
Writes scan/cut_check.json and prints counts.
"""
import difflib
import json
import os
import random
import re
import subprocess

import numpy as np

os.environ.setdefault("HF_HOME", "/mnt/sata1tb/di-whisper/hf")
from faster_whisper import WhisperModel  # noqa: E402

T = json.load(open("arabic/timings.json", encoding="utf-8"))["surahs"]
cuts = {(r["s"], r["a"]): r for r in json.load(open("scan/cuts.json"))}
DIAC = re.compile(r"[ؐ-ًؚ-ٰٟۖ-ۭـ‏]")
FOLD = str.maketrans({"أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ى": "ي", "ة": "ه", "ؤ": "و", "ئ": "ي", "ء": ""})


def norm(w):
    return re.sub(r"[^ء-ي]", "", DIAC.sub("", w).translate(FOLD))


SUSPECT = [14, 37, 60, 78, 82]
random.seed(5)
pool = [(int(s), v["ayah"]) for s, x in T.items() if int(s) not in SUSPECT for v in x["verses"][1:-1]]
targets = [(s, v["ayah"]) for s in SUSPECT for v in T[str(s)]["verses"][:-1]] + random.sample(pool, 150)
model = WhisperModel("large-v3", device="cuda", compute_type="float16")
audio = {}


def load(s):
    if s not in audio:
        raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", f"arabic/{s}.mp3", "-f", "f32le", "-ac", "1", "-ar", "16000", "-"],
                             capture_output=True, check=True).stdout
        audio.clear()
        audio[s] = np.frombuffer(raw, np.float32)
    return audio[s]


def judge(s, a, start, stop):
    x = load(s)[int(start * 16):int(stop * 16)]
    if len(x) < 1600:
        return {"empty": True}
    segs, _ = model.transcribe(x, language="ar", beam_size=5, temperature=0.0, condition_on_previous_text=False, vad_filter=False)
    heard = [norm(w) for seg in segs for w in seg.text.split() if norm(w)]
    vs = {v["ayah"]: v for v in T[str(s)]["verses"]}
    own = [norm(w["text"]) for w in vs[a]["words"] if norm(w["text"])]
    nxt = [norm(w["text"]) for w in vs[a + 1]["words"] if norm(w["text"])] if a + 1 in vs else []
    prev = [norm(w["text"]) for w in vs[a - 1]["words"] if norm(w["text"])] if a - 1 in vs else []
    def near(w, ws):
        return any(difflib.SequenceMatcher(None, w, h).ratio() >= 0.75 for h in ws)
    tail = heard[-2:]
    head = heard[:2]
    return {"first": bool(own) and near(own[0], head + heard[:3]), "last": bool(own) and near(own[-1], tail + heard[-3:]),
            "next_in": bool(nxt) and near(nxt[0], tail) and not near(own[-1], tail[-1:]),
            "prev_in": bool(prev) and near(prev[-1], head) and not near(own[0], head[:1]),
            "ratio": round(difflib.SequenceMatcher(None, "".join(own), "".join(heard)).ratio(), 2)}


out = []
for s, a in targets:
    vs = {v["ayah"]: v for v in T[str(s)]["verses"]}
    old = (vs[a]["fromMs"], vs[a]["toMs"])
    before = cuts.get((s, a - 1))
    here = cuts.get((s, a))
    new_start = before["start"] if before and before["status"] in ("fixed", "aligned") else old[0]
    new_stop = here["stop"] if here and here["status"] in ("fixed", "aligned") else old[1]
    row = {"s": s, "a": a, "old": judge(s, a, *old), "new": judge(s, a, new_start, new_stop),
           "status": here["status"] if here else None}
    out.append(row)
json.dump(out, open("scan/cut_check.json", "w"))


def summary(rows, label):
    for k in ("old", "new"):
        good = [r[k] for r in rows if "first" in r[k]]
        print(f"{label} {k}: {len(good)} clips; whole ayah (first+last word, ratio>=.6) {sum(g['first'] and g['last'] and g['ratio'] >= .6 for g in good)}; "
              f"next ayah heard {sum(g['next_in'] for g in good)}; previous ayah heard {sum(g['prev_in'] for g in good)}; median ratio {np.median([g['ratio'] for g in good]):.2f}")


summary([r for r in out if r["s"] in SUSPECT], "surahs 14/37/60/78/82")
summary([r for r in out if r["s"] not in SUSPECT], "controls")
for s in SUSPECT:
    summary([r for r in out if r["s"] == s], f"  {s}")
