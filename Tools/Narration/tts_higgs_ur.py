#!/usr/bin/env python3
"""Narrate the Silsila's Urdu translation and tafsir with Higgs TTS 3.

The owner chose Higgs (plain) for Urdu after the 2026-10-28 voice pilot. Each
sentence is one request to the Higgs server (SGLang-Omni on :8000, started by
higgs_serve.sh) in the voice of the 18-second reference clip, read slowly, with
a pause token wherever the printed text runs clauses together. The words are
never changed: only pause marks, and vowel marks on words the voice misreads
(PRONOUNCE), are added for the voice. Qur'anic Arabic quoted in the tafsir is
not read by the Urdu voice: the Qari's recitation of that ayah plays instead.

One MP3 per ayah (translation) or per passage (tafsir), translation first.
Resumable: a file that exists is never remade. STOP file = stop between items.

    tts_higgs_ur.py
"""

from __future__ import annotations

import io
import json
import re
import statistics
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import numpy as np
import requests
import soundfile as sf

sys.path.insert(0, str(Path(__file__).resolve().parent))
import narration_finish as finishing  # noqa: E402
from urdu_spoken import HONORIFICS, LETTER_AYAT, spell_letters  # noqa: E402

V = Path("/mnt/sata1tb/di-voices")
OUT = V / "quran-higgs"
STOP = V / "STOP"
FLAGGED = V / "higgs_flagged.json"
# Wording corrected against the printed Akram-ut-Tarajum (tarajum_check.py),
# keyed "surah:ayah"; the website the text was typed from has typing errors.
CORRECTIONS = V / "text_corrections.json"
# Files to make again (the check found words the voice added or dropped):
# one "edition/kind/name" per line. Each is remade and checked again.
REDO = V / "redo.txt"
ITEMS = [item for item in json.loads(Path("/mnt/sata1tb/di-tts/tts_input.json").read_text(encoding="utf-8"))
         if item["voice"] == "ur"]
ITEMS.sort(key=lambda item: (item["kind"] != "translation", item["surah"], item["ayahStart"]))
CORRECTED = json.loads(CORRECTIONS.read_text(encoding="utf-8")) if CORRECTIONS.exists() else {}
# Remake only what redo.txt lists (and nothing new) when started with --redo.
REDO_ONLY = "--redo" in sys.argv
REF_AUDIO = str(V / "refs/ur/002186.wav")
REF_TEXT = json.loads((V / "refs/ref_texts.json").read_text(encoding="utf-8"))["ur/002186"]
LEAD = "<|prosody:speed_slow|>"
PAUSE = " <|prosody:pause|> "
SENTENCE_GAP, PARAGRAPH_GAP = 0.65, 1.1
# Every piece fades in and out, so no join clicks. The file's own start and
# end (hiss out, cut to the speech, an even pause) are narration_finish's.
FADE_IN, FADE_OUT = 0.01, 0.03
MAX_CHUNK = 240

# Words the voice misreads, with the vowel marks that make it read them right.
PRONOUNCE = {
    "کرسی": "کُرسی",
}
# Words the typesetting ran together ("اورزمین", "جوکچھ", "لاسکتے").
JOINED = [
    (re.compile(r"(?<![؀-ۿ])اور(?=(اس|ان|زمین|جو|وہ|یہ|آپ|اللہ|پھر|نہ|جب|میں|ہم)(?![؀-ۿ]))"), "اور "),
    (re.compile(r"(?<![؀-ۿ])جوکچھ"), "جو کچھ"),
    (re.compile(r"(?<![؀-ۿ])(لا|جا|ہو|کر|دے|لے)(سک)"), r"\1 \2"),
]
# Clause-ending verbs: a pause after one, when more of the sentence follows.
CLAUSE_ENDS = ("ہے", "ہیں", "تھا", "تھی", "تھے", "گا", "گی", "گے", "ہوں")
# "نہیں" usually comes before its verb ("نہیں لا سکتے"); it ends a clause only
# when a new subject follows ("لائق نہیں | وہ زندہ ہے").
SUBJECTS = ("وہ", "یہ", "میں", "ہم", "آپ", "تم", "اللہ", "جو")
TERMINAL = ("۔", "؟", "!", ":", "?", ".")

ARABIC_MARKS = re.compile(r"[ً-ْٰۖ-ۭ]")
AYAH_MARKER = re.compile(r"﴿\s*([0-9٠-٩۰-۹]+)\s*﴾")
CLAUSE_WORDS = ("اور", "کہ", "تو", "لیکن", "مگر", "تاکہ", "بلکہ", "یعنی", "جبکہ", "پھر")


def log(message: str) -> None:
    print(f"[{datetime.now().strftime('%F %T')}] {message}", flush=True)


def number(text: str) -> int:
    return int(text.translate(str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789")))


def pronounce(text: str) -> str:
    for symbol, spoken in HONORIFICS.items():
        text = text.replace(symbol, spoken)
    for pattern, replacement in JOINED:
        text = pattern.sub(replacement, text)
    text = " ".join(text.split())
    for word, marked in PRONOUNCE.items():
        text = re.sub(rf"(?<![\w؀-ۿ]){word}(?![\w؀-ۿ])", marked, text)
    return text


def with_pauses(sentence: str) -> str:
    """Pause marks ("|") at commas, around bracketed notes, and before a
    clause word when the words since the last pause have run long."""
    sentence = re.sub(r"\s*\(\s*", " | (", sentence)
    sentence = re.sub(r"\s*\)\s*", ") | ", sentence)
    sentence = re.sub(r"([،,؛;:])\s*", r"\1 | ", sentence)
    words, out, since = sentence.split(), [], 0
    for position, word in enumerate(words):
        if word == "|":
            since = 0
        elif word in CLAUSE_WORDS and since >= 25:
            out.append("|")
            since = 0
        out.append(word)
        since += len(word) + 1
        # "…لائق نہیں | وہ زندہ ہے | ہمیشہ…": a clause ends at its verb.
        following = words[position + 1] if position + 1 < len(words) else None
        ends = word in CLAUSE_ENDS or (word == "نہیں" and following in SUBJECTS)
        if (ends and since >= 25 and following and following != "|"
                and following not in CLAUSE_WORDS and following not in CLAUSE_ENDS):
            out.append("|")
            since = 0
    text = " ".join(out)
    text = re.sub(r"(\|\s*)+", "| ", text)
    return text.strip(" |")


def chunks(sentence: str) -> list[str]:
    """A long sentence is read in pieces cut at its pause marks."""
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


def script(item: dict) -> list[dict]:
    """The reading script: sentences ("say"), paragraph breaks and the Qari's
    recitation of a quoted ayah ("recite")."""
    segments: list[dict] = []
    text = item["text"]
    if item["kind"] == "translation":
        text = CORRECTED.get(f"{item['surah']}:{item['ayahStart']}", text)
        if (item["surah"], item["ayahStart"]) in LETTER_AYAT:
            text = spell_letters(text)
    # A line the scan broke mid-sentence joins the next ("وہ گمراہ ⏎ ہے").
    paragraphs: list[str] = []
    for block in re.split(r"\n\s*\n", text):
        block = block.strip()
        if paragraphs and paragraphs[-1] and not paragraphs[-1].rstrip(" -").endswith(TERMINAL) \
                and not AYAH_MARKER.search(paragraphs[-1][-12:]):
            paragraphs[-1] += " " + block
        else:
            paragraphs.append(block)
    for paragraph in paragraphs:
        paragraph = " ".join(paragraph.split())
        if not paragraph:
            continue
        # Qur'anic Arabic in the tafsir ends with its ayah marker: what comes
        # before the marker in this paragraph is the verse itself.
        while (marker := AYAH_MARKER.search(paragraph)):
            verse, paragraph = paragraph[:marker.start()], paragraph[marker.end():]
            ayah = number(marker.group(1))
            if ARABIC_MARKS.search(verse) and item["ayahStart"] <= ayah <= item["ayahEnd"]:
                segments.append({"recite": f"{item['surah']:03d}{ayah:03d}"})
            elif verse.strip() and not ARABIC_MARKS.search(verse):
                paragraph = verse + " " + paragraph
        for sentence in re.split(r"(?<=[۔؟!])\s+|\s+-\s*$", paragraph):
            sentence = sentence.strip(" -")
            if sentence and not (ARABIC_MARKS.search(sentence) and len(ARABIC_MARKS.findall(sentence)) > len(sentence) / 6):
                segments.append({"say": with_pauses(pronounce(sentence))})
        segments.append({"para": True})
    while segments and "para" in segments[-1]:
        segments.pop()
    return segments


class Voice:
    def __init__(self) -> None:
        self.rate: int | None = None
        self.chars_per_second: list[float] = []

    def say(self, text: str) -> tuple[np.ndarray, bool]:
        body = {"input": LEAD + text.replace("|", PAUSE),
                "references": [{"audio_path": REF_AUDIO, "text": REF_TEXT}],
                "temperature": 0.7, "top_k": 50, "max_new_tokens": 2048}
        best, best_error = None, None
        for attempt in range(3):
            response = requests.post("http://127.0.0.1:8000/v1/audio/speech", json=body, timeout=900)
            response.raise_for_status()
            audio, rate = sf.read(io.BytesIO(response.content), dtype="float32")
            audio = audio if audio.ndim == 1 else audio.mean(axis=1)
            self.rate = self.rate or rate
            seconds = len(audio) / rate
            spoken = len(text.replace("|", ""))
            if len(self.chars_per_second) < 30:
                self.chars_per_second.append(spoken / max(seconds, 0.1))
                return audio, False
            expected = spoken / statistics.median(self.chars_per_second)
            error = abs(np.log(seconds / expected))
            if best is None or error < best_error:
                best, best_error = audio, error
            if 0.5 * expected <= seconds <= 2.0 * expected:
                self.chars_per_second.append(spoken / seconds)
                return audio, False
        return best, True


def recitation(name: str, rate: int) -> np.ndarray:
    clip = V / f"refs/recite/{name}.mp3"
    clip.parent.mkdir(parents=True, exist_ok=True)
    if not clip.exists():
        subprocess.run(["curl", "-s", "-m", "60", "-f", "-o", str(clip), f"https://everyayah.com/data/Alafasy_128kbps/{name}.mp3"],
                       check=True)
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(clip), "-f", "f32le", "-ac", "1", "-ar", str(rate), "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def faded(audio: np.ndarray, rate: int, fade_in: float = FADE_IN, fade_out: float = FADE_OUT) -> np.ndarray:
    audio = audio.astype(np.float32, copy=True)
    n_in, n_out = min(len(audio), int(rate * fade_in)), min(len(audio), int(rate * fade_out))
    if n_in:
        audio[:n_in] *= np.linspace(0.0, 1.0, n_in, dtype=np.float32)
    if n_out:
        audio[-n_out:] *= np.linspace(1.0, 0.0, n_out, dtype=np.float32)
    return audio


def gpu_temperature() -> int:
    out = subprocess.run(["nvidia-smi", "--query-gpu=temperature.gpu", "--format=csv,noheader,nounits"],
                         check=True, capture_output=True, text=True).stdout
    return int(out.split()[0])


def main() -> int:
    voice = Voice()
    redo = set(REDO.read_text().split()) if REDO.exists() else set()
    flagged = json.loads(FLAGGED.read_text()) if FLAGGED.exists() else {}
    made = 0
    started = time.monotonic()
    for index, item in enumerate(ITEMS):
        if STOP.exists():
            log("stop requested; leaving off here")
            return 4
        name = f"{item['surah']:03d}{item['ayahStart']:03d}" + (f"-{item['ayahEnd']:03d}" if item["ayahEnd"] != item["ayahStart"] else "")
        key = f"{item['edition']}/{item['kind']}/{name}"
        target = OUT / item["edition"] / item["kind"] / f"{name}.mp3"
        if (target.exists() or REDO_ONLY) and key not in redo:
            continue
        if gpu_temperature() >= 83:
            log("GPU hot, pausing")
            while gpu_temperature() >= 70:
                time.sleep(30)
        pieces, bad = [], False
        for segment in script(item):
            if "say" in segment:
                for chunk in chunks(segment["say"]):
                    audio, flag = voice.say(chunk)
                    bad |= flag
                    pieces += [faded(audio, voice.rate), np.zeros(int(voice.rate * SENTENCE_GAP), np.float32)]
            elif "para" in segment and pieces:
                pieces[-1] = np.zeros(int(voice.rate * PARAGRAPH_GAP), np.float32)
            elif "recite" in segment and voice.rate:
                try:
                    pieces += [np.zeros(int(voice.rate * 0.3), np.float32), faded(recitation(segment["recite"], voice.rate), voice.rate, 0.02, 0.15),
                               np.zeros(int(voice.rate * 0.8), np.float32)]
                except subprocess.CalledProcessError:
                    log(f"no recitation for {segment['recite']}; left out")
        if not pieces:
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        body = np.concatenate(pieces[:-1] if len(pieces) > 1 else pieces)
        if voice.rate != finishing.RATE:
            body = np.interp(np.linspace(0, len(body) - 1, int(len(body) * finishing.RATE / voice.rate)),
                             np.arange(len(body)), body).astype(np.float32)
        finishing.encode(finishing.finish(body), target)
        with (V / f"finished_{item['kind']}.txt").open("a") as done:
            done.write(str(target) + "\n")
        if key in redo:
            redo.discard(key)
            REDO.write_text("\n".join(sorted(redo)) + ("\n" if redo else ""))
        if bad:
            flagged[f"{item['edition']}/{item['kind']}/{name}"] = "length far from expected after 3 tries"
            FLAGGED.write_text(json.dumps(flagged, indent=1))
        made += 1
        if made % 50 == 0:
            rate = made / (time.monotonic() - started)
            log(f"{index + 1}/{len(ITEMS)} ({item['kind']} {name}); {made} made this run, {len(flagged)} flagged, "
                f"{rate * 3600:.0f} items/h")
    log(f"all done: {made} made this run, {len(flagged)} flagged")
    return 0


if __name__ == "__main__":
    sys.exit(main())
