#!/usr/bin/env python3
"""Check every Urdu narration against the text it should read, word for word.

The owner found Al-Ikhlas 112:4 opening with words the voice made up ("اور
پاس ہوں تو یوں میں ..."). Higgs is a generative voice, so any file can carry
words the text does not have, or drop some. Whisper (large-v3) transcribes each
file and the transcript is aligned with the source text, letter by letter with
spaces and vowel marks removed (Urdu spacing varies: "جوکچھ" / "جو کچھ").
Whisper mishears a letter here and there, so a file is flagged only for a run
of letters the voice added, dropped or replaced - the size of a word or more.

A word said twice where the text has it once ("سو سو دانے", 2:261) and a
stretch of words the text does not have (6:63 "تو ان کو چاہیے", from the
voice's reference clip; 3:17 a phrase said twice) are flagged too: letter by
letter they split into runs too short to count.

Writes verify_<kind>.json: {name: {ratio, added, dropped, replaced, moved,
repeated, inserted, heard, flag}}.
Resumable; a file whose mp3 is newer than its result is checked again.

    verify_narration.py [translation|tafsir] [--device cuda|cpu] [names...]
    verify_narration.py translation --rescore   compare the stored transcripts
                                                  again (texts corrected since)
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import numpy as np

os.environ.setdefault("HF_HOME", "/mnt/sata1tb/di-whisper/hf")
from faster_whisper import WhisperModel  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from urdu_spoken import drop_digits, spoken  # noqa: E402

V = Path("/mnt/sata1tb/di-voices")
ROOT = V / "quran-higgs"
INPUT = Path("/mnt/sata1tb/di-tts/tts_input.json")
CORRECTIONS = V / "text_corrections.json"

MARKS = re.compile(r"[ؐ-ًؚ-ٰٟۖ-ۭـ]")
NOT_LETTER = re.compile(r"[^ء-غف-يٱ-ۓ]")
FOLD = str.maketrans({"ي": "ی", "ى": "ی", "ك": "ک", "ه": "ہ", "ۀ": "ہ", "ۂ": "ہ", "ة": "ہ", "ۃ": "ہ",
                      "أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ؤ": "و", "ئ": "ی", "ۓ": "ے", "ھ": "ہ"})
# A run this long (in letters) is a word or more: added, dropped or replaced.
ADDED, DROPPED, REPLACED, RATIO = 5, 6, 9, 0.80
# Letters a stretch of heard words may add over the words of the text it lines
# up with before it counts as words the voice put in.
INSERTED = 6


def letters(text: str) -> str:
    return NOT_LETTER.sub("", MARKS.sub("", text).translate(FOLD))


def compare(source: str, heard: str) -> dict:
    a, b = letters(source), letters(heard)
    matcher = difflib.SequenceMatcher(None, a, b, autojunk=False)
    added = dropped = replaced = 0
    for op, i1, i2, j1, j2 in matcher.get_opcodes():
        if op == "insert":
            added = max(added, j2 - j1)
        elif op == "delete":
            dropped = max(dropped, i2 - i1)
        elif op == "replace":
            replaced = max(replaced, max(i2 - i1, j2 - j1))
    ratio = matcher.ratio()
    moved = moved_breaks(source, heard, matcher)
    twice, extra = repeated(source, heard), inserted(source, heard)
    flag = (added >= ADDED or dropped >= DROPPED or replaced >= REPLACED or ratio < RATIO or moved > 0
            or twice > 0 or extra >= INSERTED)
    return {"ratio": round(ratio, 3), "added": added, "dropped": dropped, "replaced": replaced, "moved": moved,
            "repeated": twice, "inserted": extra, "flag": flag}


def repeated(source: str, heard: str) -> int:
    """Words the voice said twice where the text has them once: the transcript
    matches the text better without the copy. A doubled phrase the text has
    ("طرح طرح") or Whisper's own spelling of one ("ترہ ترہ") is not counted."""
    text, said = letters(source), [letters(word) for word in heard.split()]
    written = [letters(word) for word in source.split()]
    pairs = set(zip(written, written[1:]))
    base = difflib.SequenceMatcher(None, text, "".join(said), autojunk=False).ratio()
    count = 0
    for i in range(len(said) - 1):
        word = said[i]
        if len(word) >= 2 and word == said[i + 1] and word in written and (word, word) not in pairs:
            without = "".join(said[:i + 1] + said[i + 2:])
            if difflib.SequenceMatcher(None, text, without, autojunk=False).ratio() > base:
                count += 1
    return count


def inserted(source: str, heard: str) -> int:
    """The most letters a stretch of heard words adds over the words of the
    text it lines up with."""
    written = [word for word in (letters(w) for w in source.split()) if word]
    said = [word for word in (letters(w) for w in heard.split()) if word]
    worst = 0
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, written, said, autojunk=False).get_opcodes():
        if op != "equal":
            worst = max(worst, len("".join(said[j1:j2])) - len("".join(written[i1:i2])))
    return worst


def breaks(text: str) -> set[int]:
    """Where the word breaks fall, counted in letters."""
    positions, count = set(), 0
    for word in MARKS.sub("", text).translate(FOLD).split():
        count += len(NOT_LETTER.sub("", word))
        positions.add(count)
    return positions


def moved_breaks(source: str, heard: str, matcher: difflib.SequenceMatcher) -> int:
    """Word breaks the voice moved by a letter or two: the same letters, other
    words ("اندھیرا چھا" said as "اندھیر اچھا"). Only inside stretches where
    the letters agree; a break merely present or absent is not counted."""
    to_heard = {}
    for a, b, size in matcher.get_matching_blocks():
        for offset in range(size + 1):
            to_heard[a + offset] = b + offset
    said, written = breaks(heard), breaks(source)
    moved = 0
    for position in written:
        if position not in to_heard or to_heard[position] in said:
            continue
        near = {to_heard.get(position + d) for d in (-2, -1, 1, 2)} & said
        if any(back not in written for back in (p for p, h in to_heard.items() if h in near)):
            moved += 1
    return moved


def decode(path: Path) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", "16000", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32)


def sources(kind: str) -> dict[str, str]:
    corrections = json.loads(CORRECTIONS.read_text(encoding="utf-8")) if CORRECTIONS.exists() else {}
    texts = {}
    for item in json.loads(INPUT.read_text(encoding="utf-8")):
        if item["voice"] != "ur" or item["kind"] != kind:
            continue
        name = f"{item['surah']:03d}{item['ayahStart']:03d}" + (f"-{item['ayahEnd']:03d}" if item["ayahEnd"] != item["ayahStart"] else "")
        text = drop_digits(corrections.get(f"{item['surah']}:{item['ayahStart']}", item["text"])) if kind == "translation" else item["text"]
        # Compared with what the voice was asked to say: honorifics in full,
        # the disjointed letters by name (urdu_spoken).
        texts[f"{item['edition']}/{kind}/{name}"] = spoken(text, item["surah"], item["ayahStart"])
    return texts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", nargs="?", default="translation")
    parser.add_argument("--device", default="cuda")
    parser.add_argument("--rescore", action="store_true")
    parser.add_argument("names", nargs="*")
    args = parser.parse_args()
    out = V / f"verify_{args.kind}.json"
    results = json.loads(out.read_text(encoding="utf-8")) if out.exists() else {}
    if args.rescore:
        texts = sources(args.kind)
        for key, result in results.items():
            if key in texts:
                result.update(compare(texts[key], result["heard"]))
        out.write_text(json.dumps(results, ensure_ascii=False, indent=0), encoding="utf-8")
        print(f"rescored {len(results)}: {sum(r['flag'] for r in results.values())} flagged", flush=True)
        return 0
    model = WhisperModel("large-v3", device=args.device, compute_type="float16" if args.device == "cuda" else "int8")
    texts = sources(args.kind)
    done = 0
    for key, text in sorted(texts.items()):
        name = key.rsplit("/", 1)[1]
        if args.names and name not in args.names:
            continue
        path = ROOT / f"{key}.mp3"
        if not path.exists():
            continue
        if key in results and results[key].get("mtime") == path.stat().st_mtime and not args.names:
            continue
        segments, _ = model.transcribe(decode(path), language="ur", beam_size=5, temperature=0.0,
                                       condition_on_previous_text=False, vad_filter=False)
        heard = " ".join(segment.text.strip() for segment in segments)
        results[key] = {**compare(text, heard), "heard": heard, "mtime": path.stat().st_mtime}
        done += 1
        if done % 200 == 0:
            out.write_text(json.dumps(results, ensure_ascii=False, indent=0), encoding="utf-8")
            print(f"{done} checked, {sum(r['flag'] for r in results.values())} flagged", flush=True)
    out.write_text(json.dumps(results, ensure_ascii=False, indent=0), encoding="utf-8")
    print(f"done: {len(results)} checked, {sum(r['flag'] for r in results.values())} flagged", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
