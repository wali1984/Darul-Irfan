#!/usr/bin/env python3
"""Where the table does not fit the recording (surahs 14, 37, 60, 78, 82; the
energy check found no pause at their ayah ends), place each ayah start from
Whisper: the table\x27s own word timings are matched to the words Whisper heard,
and an ayah\x27s offset is the median gap over its matched words, less Whisper\x27s
usual lead (measured on control surahs 2, 18, 67: 250 ms early). The predicted
start of each next ayah goes to cuts_build.py, which snaps it to the end of the
nearest real pause. Controls report how well the method agrees with the table.
"""
import difflib, json, re
from pathlib import Path
import numpy as np
T = json.load(open("arabic/timings.json", encoding="utf-8"))["surahs"]
DIAC = re.compile(r"[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u0640\u200f]")
FOLD = str.maketrans({"أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ى": "ي", "ة": "ه", "ؤ": "و", "ئ": "ي", "ء": ""})
SUSPECT = {"14", "37", "60", "78", "82"}
BIAS = -250
def norm(w):
    return re.sub(r"[^\u0621-\u064A]", "", DIAC.sub("", w).translate(FOLD))
overrides, report = {}, {}
for line in open("scan/words_ar.jsonl", encoding="utf-8"):
    r = json.loads(line); key = Path(r["file"]).stem
    heard = [(s, e, norm(w)) for s, e, w in r["words"] if norm(w)]
    ref = [(v["ayah"], w["startMs"], norm(w["text"])) for v in T[key]["verses"] for w in v["words"] if norm(w["text"])]
    sm = difflib.SequenceMatcher(None, [h[2] for h in heard], [x[2] for x in ref], autojunk=False)
    gaps = {}
    for a, b, n in sm.get_matching_blocks():
        for k in range(n):
            gaps.setdefault(ref[b + k][0], []).append(heard[a + k][0] * 1000 - ref[b + k][1] - BIAS)
    off = {a: float(np.median(v)) for a, v in gaps.items() if len(v) >= 2}
    vs = T[key]["verses"]; moved = []
    for i, v in enumerate(vs[:-1]):
        b = vs[i + 1]["ayah"]
        if b in off:
            moved.append(off[b])
            if key in SUSPECT:
                overrides[key + ":" + str(v["ayah"])] = int(vs[i + 1]["fromMs"] + off[b])
    m = np.abs(moved) if moved else np.array([0])
    report[key] = {"ayat": len(moved), "median_abs_shift_ms": int(np.median(m)), "p90_abs_shift_ms": int(np.percentile(m, 90)), "over_300ms": int((m > 300).sum())}
    print(key, report[key])
Path("scan/cut_overrides.json").write_text(json.dumps(overrides))
Path("scan/align_report.json").write_text(json.dumps(report))
print(len(overrides), "ayah starts placed from the alignment")
