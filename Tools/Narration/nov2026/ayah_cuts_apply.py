#!/usr/bin/env python3
"""Write measured ayah cut points into a copy of quran_word_timings.json.

NOT run by the November work: it prepares the content change for a release.
The input table (scan/ayah_cuts_validated.json: cuts_build.py, and for surahs
14, 37, 60, 78, 82 only the starts Whisper confirmed in cut_check.py
) gives, per ayah end, where the player should stop
(`stop`, inside the reciter's pause) and where the next ayah should start
(`start`). The apps start and stop 40 ms before the timings (iOS QuranListenCut,
Android ListenPlan.clipStartMs/clipEndMs), so the file gets those plus 40 ms.
Only verse fromMs/toMs change; word timings, words and their text are untouched,
and nothing of the Qur'an text is read or written.

    ayah_cuts_apply.py <cuts.json> <in quran_word_timings.json> <out.json>

To ship (content release): run against the iOS seed, copy the result to the iOS
and Android seed paths (DarulIrfan-iOS/DarulIrfanApp/Resources/SeedData and the
Android assets copy), bump the content manifest as for any seed change, and run
the Android unit tests (HifzPlaybackTimelineTest reads these windows).
"""
import json
import sys

GUARD = 40
cuts = json.load(open(sys.argv[1]))
data = json.load(open(sys.argv[2], encoding="utf-8"))
changed = 0
for row in cuts:
    if row.get("status") not in ("fixed", "aligned-checked"):
        continue
    verses = data["surahs"][str(row["s"])]["verses"]
    by = {v["ayah"]: v for v in verses}
    this, nxt = by.get(row["a"]), by.get(row["a"] + 1)
    if not this or not nxt:
        continue
    to = row["stop"] + GUARD
    start = max(to, row["start"] + GUARD)
    if to <= this["fromMs"] or start >= nxt["toMs"]:
        continue
    if (this["toMs"], nxt["fromMs"]) != (to, start):
        this["toMs"], nxt["fromMs"] = to, start
        changed += 1
json.dump(data, open(sys.argv[3], "w", encoding="utf-8"), ensure_ascii=False)
print(f"{changed} ayah boundaries moved")
