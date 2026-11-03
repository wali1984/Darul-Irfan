#!/usr/bin/env python3
"""Pace and mispronunciation clusters from the stored Whisper transcripts (CPU).

A word whose heard form disagrees with the text across many ayat, while Whisper
hears other words right, is a likely misreading; one-off differences are
Whisper's spelling. Also pace: letters per second from file duration.
"""
import collections
import difflib
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, "/mnt/sata1tb/di-voices")
import numpy as np
from urdu_spoken import drop_digits, spoken

V = Path("/mnt/sata1tb/di-voices")
res = json.load(open(V / "verify_translation.json", encoding="utf-8"))
corr = json.load(open(V / "text_corrections.json", encoding="utf-8"))
texts = {}
for it in json.load(open("/mnt/sata1tb/di-tts/tts_input.json", encoding="utf-8")):
    if it["voice"] == "ur" and it["kind"] == "translation":
        name = f"{it['surah']:03d}{it['ayahStart']:03d}"
        texts[f"{it['edition']}/translation/{name}"] = spoken(drop_digits(corr.get(f"{it['surah']}:{it['ayahStart']}", it["text"])), it["surah"], it["ayahStart"])

import re
MARKS = re.compile(r"[ؐ-ًؚ-ٰٟۖ-ۭـ]")
NOT = re.compile(r"[^ء-غف-يٱ-ۓ]")
FOLD = str.maketrans({"ي": "ی", "ى": "ی", "ك": "ک", "ه": "ہ", "ۀ": "ہ", "ۂ": "ہ", "ة": "ہ", "ۃ": "ہ", "أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ؤ": "و", "ئ": "ی", "ۓ": "ے", "ھ": "ہ"})


def clean(w):
    return NOT.sub("", MARKS.sub("", w).translate(FOLD))


pairs = collections.Counter()
seen = collections.Counter()
missed = collections.Counter()
places = collections.defaultdict(list)
for key, r in res.items():
    if key not in texts:
        continue
    a = [clean(w) for w in texts[key].split()]
    a = [w for w in a if w]
    b = [w for w in (clean(w) for w in r["heard"].split()) if w]
    for w in a:
        seen[w] += 1
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if op == "replace" and i2 - i1 == 1 and j2 - j1 == 1:
            pairs[(a[i1], b[j1])] += 1
            missed[a[i1]] += 1
            places[(a[i1], b[j1])].append(key.rsplit("/", 1)[1])
out = []
for (w, h), n in pairs.most_common():
    if n < 4:
        break
    ratio = difflib.SequenceMatcher(None, w, h).ratio()
    out.append({"word": w, "heard": h, "n": n, "of": seen[w], "share": round(n / seen[w], 2), "sim": round(ratio, 2), "places": places[(w, h)][:6]})
Path("scan/pron_pairs.json").write_text(json.dumps(out, ensure_ascii=False, indent=0), encoding="utf-8")
print("pairs >=4:", len(out))
print("repeat misheard words total", sum(x["n"] for x in out))
for x in out[:70]:
    print(x["word"], "->", x["heard"], x["n"], "/", x["of"], x["places"][:2])
scan = {x["file"].rsplit("/", 1)[1][:-4]: x for x in json.load(open("scan/h2_ur.json"))}
cps = []
for k, t in texts.items():
    n = k.rsplit("/", 1)[1]
    if n in scan and "seconds" in scan[n]:
        L = len(clean(t.replace(" ", "")))
        if L > 25:
            cps.append((L / max(scan[n]["seconds"] - 0.5, 0.5), n))
v = np.array([c for c, _ in cps])
print("letters per second pct5,25,50,75,95,99", np.round(np.percentile(v, [5, 25, 50, 75, 95, 99]), 1), "fastest", sorted(cps, reverse=True)[:6])
