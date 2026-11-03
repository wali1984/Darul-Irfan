#!/usr/bin/env python3
"""Does a vowel mark fix a word? Each suspect word from the Whisper clusters is
read in a real ayah, plain and marked, 2 takes each. Output: per word how often
Whisper hears the written word (GPU: run the Higgs part then the Whisper part).

    pron_bench.py make | hear | score
"""
import json
import re
import sys
from pathlib import Path

N = Path("/mnt/sata1tb/di-voices/nov-fixes")
sys.path.insert(0, str(N))
sys.argv, ARGS = sys.argv[:1], sys.argv[1:]
OUT = N / "pron"
# Meaning or sound really at risk (not Whisper's spelling of ص/س, ذ/ز, ع/ا).
CANDIDATES = {
    "سات": ["سَات"], "پوجتے": ["پُوجتے"], "مانگتا": ["مَانگتا", "مانْگتا"], "پیٹھ": ["پِیٹھ"], "ڈرو": ["ڈَرو"], "ڈرانے": ["ڈَرانے"],
    "بگاڑ": ["بِگاڑ"], "پس": ["پَس"], "بخشی": ["بَخْشی"], "وحی": ["وَحی"], "مہلت": ["مُہلت"], "مقرر": ["مُقرّر"], "صلہ": ["صِلہ"],
    "لعنت": ["لَعنت"], "عنقریب": ["عَنقریب"], "معجزہ": ["مُعجزہ"], "اعمال": ["اَعمال"], "غضب": ["غَضَب"], "تکذیب": ["تَکذیب"],
    "اجر": ["اَجر"], "مذاق": ["مَذاق"], "عہد": ["عَہد"], "ہارون": ["ہارُون"], "فرعون": ["فِرعون"],
}


def places():
    import tts_higgs_v3 as tts
    res = {}
    texts = []
    for i in tts.base.ITEMS:
        if i["kind"] == "translation":
            t = tts.base.CORRECTED.get(f"{i['surah']}:{i['ayahStart']}", i["text"])
            texts.append(t)
    for w in CANDIDATES:
        hits = [t for t in texts if re.search(rf"(?<![؀-ۿ]){w}(?![؀-ۿ])", t) and 40 <= len(t) <= 160]
        res[w] = hits[:2]
    return res


def make():
    import tts_higgs_v3 as tts
    from urdu_spoken import drop_digits
    voice = tts.Voice(str(N / "refs/002186_clean.wav"), tts.base.REF_TEXT, 0.7, 11.0)
    OUT.mkdir(exist_ok=True)
    pl = places()
    (OUT / "places.json").write_text(json.dumps(pl, ensure_ascii=False))
    import soundfile as sf
    for w, hits in pl.items():
        for h, text in enumerate(hits):
            text = drop_digits(text)
            for v, form in enumerate([w] + CANDIDATES[w]):
                said = re.sub(rf"(?<![؀-ۿ]){w}(?![؀-ۿ])", form, text)
                for take in range(2):
                    path = OUT / f"{w}__{h}__{v}__{take}.wav"
                    if not path.exists():
                        sf.write(path, voice.take(tts.with_pauses(said)), voice.rate)


def score():
    import collections
    import tts_higgs_v3 as tts
    fold = str.maketrans({"ي": "ی", "ى": "ی", "ك": "ک", "ه": "ہ", "ھ": "ہ", "ة": "ہ"})
    tally = collections.defaultdict(lambda: [0, 0])
    examples = collections.defaultdict(list)
    for line in open(N / "scan/words_pron.jsonl", encoding="utf-8"):
        r = json.loads(line)
        word, h, v, _ = Path(r["file"]).stem.split("__")
        said = [tts.plain(w[2]).translate(fold) for w in r["words"]]
        target = tts.plain(word).translate(fold)
        tally[(word, int(v))][1] += 1
        if target in said:
            tally[(word, int(v))][0] += 1
    choose = {}
    for w in CANDIDATES:
        row = [(v, tally[(w, v)]) for v in range(len(CANDIDATES[w]) + 1)]
        print(w, [f"{a}/{b}" for _, (a, b) in row], CANDIDATES[w])
        base_hit = row[0][1][0] / max(row[0][1][1], 1)
        best = max(row[1:], key=lambda x: x[1][0] / max(x[1][1], 1))
        if best[1][1] and best[1][0] / best[1][1] >= base_hit + 0.25:
            choose[w] = CANDIDATES[w][best[0] - 1]
    (N / "pronounce_v3.json").write_text(json.dumps(choose, ensure_ascii=False, indent=0), encoding="utf-8")
    print("chosen", choose)


if __name__ == "__main__":
    {"make": make, "score": score}[ARGS[0]]()
