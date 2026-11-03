#!/usr/bin/env python3
"""November 2026 Urdu narration: the owner still heard hiss, AI-sounding pace
and wrong pauses in rev 2. The text read stays exactly the Silsila's; only
pause marks and vowel marks are added for the voice. Output goes to its own
folder; nothing here uploads or touches quran-higgs, the manifest or PUBLISH.

What changed from tts_higgs_ur.py:
- reference clip cleaned first (the voice copied its -48 dB floor into every take);
- pauses by clause, from punctuation and Urdu grammar: at clause verbs, before
  a clause word, and never before a postposition or auxiliary;
- every take over the pace limit is read again, and the slowest take kept;
- more words with vowel marks (PRONOUNCE, tested with pron_bench.py);
- narration_finish_v3 (no switching noise, the hot 6-9 kHz band brought down).

    tts_higgs_v3.py --out DIR [--keys @file|a/b/c ...] [--mode token|split]
                    [--ref wav] [--temp 0.7] [--max-lps 10.0] [--stretch]
"""
from __future__ import annotations

import argparse
import io
import json
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import requests
import soundfile as sf

sys.argv, ARGV = sys.argv[:1], sys.argv[1:]
sys.path.insert(0, "/mnt/sata1tb/di-voices")
sys.path.insert(0, "/mnt/sata1tb/di-voices/nov-fixes")
import tts_higgs_ur as base  # noqa: E402
import narration_finish_v3 as finishing  # noqa: E402
from urdu_spoken import drop_digits, spell_letters, LETTER_AYAT  # noqa: E402

V = Path("/mnt/sata1tb/di-voices")
N = V / "nov-fixes"
STOP = N / "STOP"
LEAD = "<|prosody:speed_slow|>"
PAUSE = " <|prosody:pause|> "
SENTENCE_GAP, PARAGRAPH_GAP, CLAUSE_GAP = 0.60, 1.05, 0.26
MAX_CHUNK = 200
pron = N / "pronounce_v3.json"
PRONOUNCE = {**base.PRONOUNCE, **(json.loads(pron.read_text(encoding="utf-8")) if pron.exists() else {})}

MARKS = re.compile(r"[ؐ-ًؚ-ٰٟۖ-ۭـ]")
# Never pause just before these: they lean on the word before.
LEANERS = {"کے", "کی", "کا", "کو", "سے", "میں", "پر", "نے", "تک", "ہی", "بھی", "ہے", "ہیں", "تھا", "تھی", "تھے", "ہوں",
           "گا", "گی", "گے", "نہیں", "رہا", "رہی", "رہے", "گیا", "گئی", "گئے", "دیا", "لیا", "ہو", "ہوا", "ہوئی", "ہوئے",
           "والا", "والے", "والی", "لیے", "لئے", "طرح", "ساتھ", "جائے", "جائیں", "سکتا", "سکتے", "سکتی", "کر", "وہی"}
# Finite verb ends: a new clause may start after these.
VERB_ENDS = {"ہے", "ہیں", "تھا", "تھی", "تھے", "گا", "گی", "گے", "ہوں", "ہو", "دیا", "لیا", "کیا", "گیا", "گئے", "گئی", "ہوا", "ہوئے"}
# Clause openers: a pause before them. "اور" also joins two nouns, so it needs
# a longer run before it unless a verb has just ended.
OPENERS = {"کہ", "تو", "لیکن", "مگر", "تاکہ", "بلکہ", "یعنی", "جبکہ", "پھر", "کیونکہ", "اگر", "جب", "پس", "چنانچہ", "حالانکہ", "جو", "جس", "جن", "جنہوں"}
SUBJECTS = {"وہ", "یہ", "میں", "ہم", "آپ", "تم", "اللہ", "جو", "ان", "اس"}
AFTER_VERB, BEFORE_OPENER, BEFORE_AND, FORCE = 12, 18, 30, 62
AFTER_LAST = 10   # letters that must remain after a pause


def plain(word: str) -> str:
    return re.sub(r"[^ء-ۓ]", "", MARKS.sub("", word))


def with_pauses(sentence: str) -> str:
    """"|" where a reader would breathe. Letter counts, not characters, so
    vowel marks do not change where the pauses fall."""
    sentence = re.sub(r"\s*\(\s*", " | (", sentence)
    sentence = re.sub(r"\s*\)\s*", ") | ", sentence)
    sentence = re.sub(r"([،,؛;:])\s*", r"\1 | ", sentence)
    words = sentence.split()
    bare = [plain(w) for w in words]
    total = [len(b) for b in bare]
    left = sum(total)
    out: list[str] = []
    since = 0
    for i, word in enumerate(words):
        b = bare[i]
        if word == "|":
            since = 0
            out.append(word)
            continue
        prev = next((bare[j] for j in range(i - 1, -1, -1) if bare[j]), "")
        pause = False
        if since and left >= AFTER_LAST and b not in LEANERS:
            if prev in VERB_ENDS and since >= AFTER_VERB:
                pause = True
            elif b in OPENERS and since >= BEFORE_OPENER:
                pause = True
            elif b == "اور" and (since >= BEFORE_AND or (prev in VERB_ENDS and since >= AFTER_VERB)):
                pause = True
            elif prev == "نہیں" and b in SUBJECTS and since >= AFTER_VERB:
                pause = True
            elif since >= FORCE and prev in {"کے", "کی", "کو", "سے", "میں", "پر", "کا", "نے", "اور"}:
                pause = prev != "اور" and prev not in {"کی", "کے", "کا"}
        if pause:
            out.append("|")
            since = 0
        out.append(word)
        since += total[i]
        left -= total[i]
    text = " ".join(out)
    text = re.sub(r"(\|\s*)+", "| ", text)
    return text.strip(" |")


def pronounce(text: str) -> str:
    for symbol, spoken_form in base.HONORIFICS.items():
        text = text.replace(symbol, spoken_form)
    for pattern, replacement in base.JOINED:
        text = pattern.sub(replacement, text)
    text = " ".join(text.split())
    for word, marked in PRONOUNCE.items():
        text = re.sub(rf"(?<![\w؀-ۿ]){word}(?![\w؀-ۿ])", marked, text)
    return text


# Reuse the reading script (corrections, recitation, paragraphs) with the new
# clause pauses and vowel marks.
base.with_pauses = with_pauses
base.pronounce = pronounce


def chunks(sentence: str) -> list[str]:
    parts, current = [], ""
    for piece in sentence.split("|"):
        piece = piece.strip()
        if not piece:
            continue
        if current and len(current) + len(piece) > MAX_CHUNK:
            parts.append(current)
            current = piece
        else:
            current = f"{current} | {piece}" if current else piece
    if current:
        parts.append(current)
    return parts


def letters_in(text: str) -> int:
    return len(plain(text.replace("|", " ").replace(" ", "")))


class Voice:
    def __init__(self, ref: str, ref_text: str, temp: float, max_lps: float) -> None:
        self.ref, self.ref_text, self.temp, self.max_lps = ref, ref_text, temp, max_lps
        self.rate = None
        self.lps: list[float] = []

    def take(self, text: str) -> np.ndarray:
        body = {"input": LEAD + text.replace("|", PAUSE), "references": [{"audio_path": self.ref, "text": self.ref_text}],
                "temperature": self.temp, "top_k": 50, "max_new_tokens": 2048}
        response = requests.post("http://127.0.0.1:8000/v1/audio/speech", json=body, timeout=900)
        response.raise_for_status()
        audio, rate = sf.read(io.BytesIO(response.content), dtype="float32")
        self.rate = self.rate or rate
        return audio if audio.ndim == 1 else audio.mean(axis=1)

    def say(self, text: str) -> tuple[np.ndarray, bool]:
        """Takes that are too fast, or far longer than the text (made-up
        words), are read again; the slowest sensible take is kept."""
        spoken_letters = letters_in(text)
        best, best_lps, sensible = None, None, False
        typical = statistics.median(self.lps) if len(self.lps) >= 30 else 8.8
        for _ in range(3):
            audio = self.take(text)
            lps = spoken_letters / max(len(audio) / self.rate, 0.1)
            ok = lps > typical / 2.0
            if best is None or (ok and (not sensible or lps < best_lps)):
                best, best_lps, sensible = audio, lps, ok
            if ok and lps <= self.max_lps:
                break
        self.lps.append(best_lps)
        return best, not sensible


def stretch(audio: np.ndarray, rate: int, tempo: float) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-f", "f32le", "-ar", str(rate), "-ac", "1", "-i", "-",
                          "-af", f"atempo={tempo:.3f}", "-f", "f32le", "-"], input=audio.astype(np.float32).tobytes(),
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32)


RECITE_LEVEL_DB = -27.0   # the Urdu voice's level; the Qari's file runs 10 dB hotter


def recited(name: str, rate: int) -> np.ndarray:
    """The Qari's recitation of a quoted ayah, at the narrator's level, cut to
    the voice and faded, so its own room noise does not switch on and off."""
    clip = base.recitation(name, rate).astype(np.float32)
    W = int(rate * .02)
    n = len(clip) // W
    lvl = 20 * np.log10(np.sqrt((clip[:n * W].reshape(n, W) ** 2).mean(1)) + 1e-9)
    loud = lvl[lvl > -60]
    if not len(loud):
        return clip
    ref = float(np.percentile(loud, 70))
    on = np.flatnonzero(lvl > ref - 30)
    clip = clip[max(0, on[0] * W - int(.03 * rate)):(on[-1] + 1) * W + int(.25 * rate)]
    clip = clip * 10 ** ((RECITE_LEVEL_DB - ref) / 20)
    return base.faded(clip, rate, 0.04, 0.2)


def faded(audio: np.ndarray, rate: int, fade_in=0.008, fade_out=0.05) -> np.ndarray:
    return base.faded(audio, rate, fade_in, fade_out)


def make(item: dict, voice: Voice, mode: str, allow_stretch: bool) -> tuple[np.ndarray | None, bool]:
    pieces: list[np.ndarray] = []
    bad = False
    for segment in base.script(item):
        if "say" in segment:
            parts = chunks(segment["say"]) if mode == "token" else [p.strip() for p in segment["say"].split("|") if p.strip()]
            for n, chunk in enumerate(parts):
                audio, flag = voice.say(chunk)
                bad |= flag
                lps = letters_in(chunk) / max(len(audio) / voice.rate, 0.1)
                if allow_stretch and lps > voice.max_lps:
                    audio = stretch(audio, voice.rate, max(0.92, voice.max_lps / lps))
                gap = SENTENCE_GAP if n == len(parts) - 1 else (CLAUSE_GAP if mode == "split" else SENTENCE_GAP)
                pieces += [faded(audio, voice.rate), np.zeros(int(voice.rate * gap), np.float32)]
        elif "para" in segment and pieces:
            pieces[-1] = np.zeros(int(voice.rate * PARAGRAPH_GAP), np.float32)
        elif "recite" in segment and voice.rate:
            try:
                pieces += [np.zeros(int(voice.rate * 0.3), np.float32), recited(segment["recite"], voice.rate),
                           np.zeros(int(voice.rate * 0.8), np.float32)]
            except subprocess.CalledProcessError:
                print("no recitation for", segment["recite"], flush=True)
    if not pieces:
        return None, bad
    body = np.concatenate(pieces[:-1] if len(pieces) > 1 else pieces)
    if voice.rate != finishing.RATE:
        body = np.interp(np.linspace(0, len(body) - 1, int(len(body) * finishing.RATE / voice.rate)),
                         np.arange(len(body)), body).astype(np.float32)
    return finishing.finish(body), bad


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--keys", nargs="*", default=None)
    parser.add_argument("--mode", default="token")
    parser.add_argument("--ref", default=str(N / "refs/002186_clean.wav"))
    parser.add_argument("--temp", type=float, default=0.7)
    parser.add_argument("--max-lps", type=float, default=10.0)
    parser.add_argument("--stretch", action="store_true")
    args = parser.parse_args(ARGV)
    keys = None
    if args.keys:
        keys = []
        for k in args.keys:
            keys += Path(k[1:]).read_text().split() if k.startswith("@") else [k]
        keys = set(keys)
    out = Path(args.out)
    voice = Voice(args.ref, base.REF_TEXT, args.temp, args.max_lps)
    flagged = out / "flagged.json"
    bad_list = json.loads(flagged.read_text()) if flagged.exists() else {}
    made = 0
    began = time.monotonic()
    for item in base.ITEMS:
        name = f"{item['surah']:03d}{item['ayahStart']:03d}" + (f"-{item['ayahEnd']:03d}" if item["ayahEnd"] != item["ayahStart"] else "")
        key = f"{item['edition']}/{item['kind']}/{name}"
        if keys is not None and key not in keys:
            continue
        target = out / item["edition"] / item["kind"] / f"{name}.mp3"
        if target.exists():
            continue
        if STOP.exists() or (V.parent / "di-queue/HALTED").exists():
            print("stop or halt: leaving off here", flush=True)
            return 4
        if base.gpu_temperature() >= 83:
            while base.gpu_temperature() >= 70:
                time.sleep(30)
        audio, bad = make(item, voice, args.mode, args.stretch)
        if audio is None:
            continue
        finishing.encode(audio, target)
        if bad:
            bad_list[key] = "take far shorter than the text after 3 tries"
            flagged.write_text(json.dumps(bad_list, indent=1))
        made += 1
        if made % 50 == 0:
            print(f"{made} made, {made / (time.monotonic() - began) * 3600:.0f}/h", flush=True)
    print(f"done: {made} made", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
