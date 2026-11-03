#!/usr/bin/env python3
"""Unnatural pauses and pace, from word-timed Whisper over a set of narrations.

For each file (JSONL from whisper_words.py):
- mid: a pause of 180 ms or more before a word that leans on the one before
  (کے کا کو میں ہے ...) or after one that needs the next (کے کی کا اس ان اور ...);
- missed: a clause boundary (punctuation or grammar, tts_higgs_v3.with_pauses)
  read with under 60 ms of pause, after 40+ letters without a pause;
- run: most letters read without a pause of 120 ms or more;
- lps: letters per second while speaking (pauses out);
- pause_at_clause: how many of the clause boundaries got a pause.

    pause_detect.py <words.jsonl> <out.json>
"""
import difflib
import json
import re
import statistics
import sys
from pathlib import Path

N = Path("/mnt/sata1tb/di-voices/nov-fixes")
sys.path.insert(0, str(N))
sys.argv, ARGS = sys.argv[:1], sys.argv[1:]
import tts_higgs_v3 as tts  # noqa: E402

base = tts.base
MID, BREATH, MISSED = 0.18, 0.12, 0.06
NEEDS_NEXT = {"کے", "کی", "کا", "اس", "ان", "ہر", "جس", "جن", "اور", "کہ", "نہ", "اپنے", "اپنی", "اپنا"}
items = {}
for i in base.ITEMS:
    name = f"{i['surah']:03d}{i['ayahStart']:03d}" + (f"-{i['ayahEnd']:03d}" if i["ayahEnd"] != i["ayahStart"] else "")
    items[f"{i['kind']}/{name}"] = i


def clean(w):
    return tts.plain(w).translate(str.maketrans({"ي": "ی", "ى": "ی", "ك": "ک", "ه": "ہ", "ھ": "ہ", "ة": "ہ", "أ": "ا", "إ": "ا", "آ": "ا", "ئ": "ی", "ؤ": "و", "ۓ": "ے"}))


def quiet_gaps(path, words):
    """Whisper stretches a word into the silence after it, so its timestamps
    do not show pauses. The pause after word i is the longest run of 10 ms
    frames 25 dB under the voice between the middle of word i and the middle
    of word i+1."""
    import subprocess
    import numpy as np
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", "16000", "-"],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.float32)
    n = len(x) // 160
    lvl = 20 * np.log10(np.sqrt((x[:n * 160].reshape(n, 160) ** 2).mean(1)) + 1e-9)
    loud = lvl[lvl > -60]
    quiet = lvl < (np.percentile(loud, 70) if len(loud) else -30) - 25
    gaps = []
    for i in range(len(words) - 1):
        a = int((words[i][0] + words[i][1]) / 2 * 100)
        b = int((words[i + 1][0] + words[i + 1][1]) / 2 * 100)
        best = run = 0
        for k in range(max(0, a), min(n, b)):
            run = run + 1 if quiet[k] else 0
            best = max(best, run)
        gaps.append(best / 100)
    return gaps + [0.0]


def analyse(item, words, path=None):
    source: list[str] = []
    ends: set[int] = set()   # index of a source word after which a clause ends
    for segment in base.script(item):
        if "say" not in segment:
            continue
        for part in segment["say"].split("|"):
            ws = [clean(w) for w in part.split()]
            ws = [w for w in ws if w]
            source += ws
            if ws:
                ends.add(len(source) - 1)
    said = [clean(w[2]) for w in words]
    gap_after = quiet_gaps(path, words)
    to_source = {}
    for a, b, size in difflib.SequenceMatcher(None, said, source, autojunk=False).get_matching_blocks():
        for k in range(size):
            to_source[a + k] = b + k
    mid = missed = run = at_clause = clauses = 0
    worst = 0
    speaking = 0.0
    letters = 0
    examples = []
    for i, w in enumerate(said):
        speaking += words[i][1] - words[i][0]
        letters += len(w)
        run += len(w)
        worst = max(worst, run)
        gap = gap_after[i]
        nxt = said[i + 1] if i + 1 < len(said) else None
        if nxt and gap >= MID and (nxt in tts.LEANERS or w in NEEDS_NEXT):
            mid += 1
            if len(examples) < 4:
                examples.append(f"{w} | {nxt} {gap:.2f}")
        s = to_source.get(i)
        if s in ends and nxt:
            clauses += 1
            if gap >= BREATH:
                at_clause += 1
            elif gap < MISSED and run >= 40:
                missed += 1
        if gap >= BREATH:
            run = 0
    return {"mid": mid, "missed": missed, "run": worst, "clauses": clauses, "at_clause": at_clause,
            "lps": round(letters / max(speaking, 0.1), 1), "words": len(said), "examples": examples,
            "tail_gap": None}


def main():
    res = {}
    for line in open(ARGS[0], encoding="utf-8"):
        r = json.loads(line)
        parts = Path(r["file"]).parts
        key = f"{parts[-2]}/{Path(r['file']).stem}"
        if key not in items or not r["words"]:
            continue
        res[r["file"]] = analyse(items[key], r["words"], N / r["file"] if not r["file"].startswith("/") else r["file"])
    Path(ARGS[1]).write_text(json.dumps(res, ensure_ascii=False))
    groups = {}
    for f, x in res.items():
        p = Path(f).parts
        g = p[1] if p[0] == "ab" else "current"
        groups.setdefault(g, []).append(x)
    for g, xs in sorted(groups.items()):
        print(f"{g}: {len(xs)} files, mid-phrase pauses {sum(x['mid'] for x in xs)} ({sum(1 for x in xs if x['mid'])} files), "
              f"missed clauses {sum(x['missed'] for x in xs)}, clause pauses {sum(x['at_clause'] for x in xs)}/{sum(x['clauses'] for x in xs)}, "
              f"longest run median {statistics.median(x['run'] for x in xs)} max {max(x['run'] for x in xs)}, "
              f"speaking lps median {statistics.median(x['lps'] for x in xs)} p95 {sorted(x['lps'] for x in xs)[int(.95 * len(xs))]}")


if __name__ == "__main__":
    main()
