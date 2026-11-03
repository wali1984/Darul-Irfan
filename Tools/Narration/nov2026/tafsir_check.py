#!/usr/bin/env python3
"""Exact-text check for tafsir narrations. The tafsir text carries the Qur'anic
Arabic it quotes; the narrator does not say it - the Qari's recording plays
there - and Whisper writes that recitation down too. So: the text compared is
what the narrator was asked to say (the script's "say" parts, the same pause and
vowel marks aside), and the heard stretch that best matches each recited ayah
is taken out before comparing, with verify_narration.compare.

    tafsir_check.py <words.jsonl> [out.json]   (Whisper venv python, CPU)
"""
import difflib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, "/mnt/sata1tb/di-voices")
sys.path.insert(0, "/mnt/sata1tb/di-voices/nov-fixes")
argv, sys.argv = sys.argv[1:], sys.argv[:1]
import verify_narration as vn  # noqa: E402
import types  # noqa: E402
for _m in ("requests", "soundfile"):  # the narrator's network/audio modules are not needed here
    sys.modules.setdefault(_m, types.ModuleType(_m))
import tts_higgs_v3 as tts  # noqa: E402

base = tts.base
quran = {}
QA = Path("/mnt/sata1tb/di-voices/nov-fixes/quran_ayahs_ar.json")
items = {}
for i in base.ITEMS:
    if i["kind"] == "tafsir":
        name = f"{i['surah']:03d}{i['ayahStart']:03d}" + (f"-{i['ayahEnd']:03d}" if i["ayahEnd"] != i["ayahStart"] else "")
        items[name] = i


def recited_texts(item):
    """The Arabic quoted before each ayah marker in the tafsir text."""
    out = []
    for paragraph in re.split(r"\n\s*\n", item["text"]):
        paragraph = " ".join(paragraph.split())
        while (m := base.AYAH_MARKER.search(paragraph)):
            verse, paragraph = paragraph[:m.start()], paragraph[m.end():]
            if base.ARABIC_MARKS.search(verse):
                out.append(verse)
    return out


def check(item, heard_words):
    said = " ".join(seg["say"].replace("|", " ") for seg in base.script(item) if "say" in seg)
    heard = [w for w in heard_words]
    letters = [vn.letters(w) for w in heard]
    removed = 0
    for verse in recited_texts(item):
        target = vn.letters(verse)
        if not target:
            continue
        best, span = 0.0, None
        # windows of heard words around the verse's length in letters
        for a in range(len(heard)):
            total = ""
            for b in range(a, len(heard)):
                total += letters[b]
                if len(total) > 1.6 * len(target):
                    break
                if len(total) >= 0.5 * len(target):
                    r = difflib.SequenceMatcher(None, target, total, autojunk=False).ratio()
                    if r > best:
                        best, span = r, (a, b + 1)
        if span and best >= 0.45:
            removed += span[1] - span[0]
            heard = heard[:span[0]] + heard[span[1]:]
            letters = letters[:span[0]] + letters[span[1]:]
    result = vn.compare(said, " ".join(heard))
    result["recitation_words_removed"] = removed
    return result


if __name__ == "__main__":
    out = {}
    for line in open(argv[0], encoding="utf-8"):
        r = json.loads(line)
        p = Path(r["file"])
        if p.parts[-2] != "tafsir" or p.stem not in items:
            continue
        res = check(items[p.stem], [w[2] for w in r["words"]])
        out[r["file"]] = res
        print(r["file"], {k: res[k] for k in ("ratio", "added", "dropped", "replaced", "repeated", "inserted", "flag", "recitation_words_removed")})
    if len(argv) > 1:
        Path(argv[1]).write_text(json.dumps(out, ensure_ascii=False))
