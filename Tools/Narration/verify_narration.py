#!/usr/bin/env python3
"""Check every Urdu narration against the text it should read, word for word.

The owner found Al-Ikhlas 112:4 opening with words the voice made up ("اور
پاس ہوں تو یوں میں ..."). Higgs is a generative voice, so any file can carry
words the text does not have, or drop some. Whisper (large-v3) transcribes each
file and the transcript is aligned with the source text, letter by letter with
spaces and vowel marks removed (Urdu spacing varies: "جوکچھ" / "جو کچھ").
Whisper mishears a letter here and there, so a file is flagged only for a run
of letters the voice added, dropped or replaced - the size of a word or more.

Writes verify_<kind>.json: {name: {ratio, added, dropped, replaced, heard, flag}}.
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
from urdu_spoken import spoken  # noqa: E402

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
    flag = added >= ADDED or dropped >= DROPPED or replaced >= REPLACED or ratio < RATIO
    return {"ratio": round(ratio, 3), "added": added, "dropped": dropped, "replaced": replaced, "flag": flag}


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
        text = corrections.get(f"{item['surah']}:{item['ayahStart']}", item["text"]) if kind == "translation" else item["text"]
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
