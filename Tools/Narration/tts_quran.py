#!/usr/bin/env python3
"""Narrate the Silsila's Qur'an translations and tafsir with OmniVoice.

Input (tts_input.json), in this order: Akram-ut-Tarajum Urdu, Akram-ut-Tarajum
English and Asrar-at-Tanzil English per ayah, then Akram-ut-Tafaseer (Urdu) and
Asrar-at-Tanzil (English) tafsir per passage.

Alignment: every file covers exactly one ayah (translations) or exactly the
ayat a tafsir passage explains, so playback starts and stops on ayah ends.
Files: quran/<edition>/<kind>/SSSAAA.mp3, or SSSAAA-EEE.mp3 for a passage that
spans ayat. Arabic Qur'an quotations inside tafsir are not voiced: a synthetic
voice must not recite the Qur'an.

Quality: each result's length is compared with what its text should take;
a reading that came out much too short (cut off) or too long (rambling) is
generated again, up to three tries, and the closest is kept and flagged.

Resumable: an existing file is never redone. Pauses when the GPU runs hot and
stops if tts_run.sh's watchdog writes STOP.
"""

from __future__ import annotations

import json
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
from omnivoice import OmniVoice

ROOT = Path("/mnt/sata1tb/di-tts")
OUT = ROOT / "quran"
STOP = ROOT / "STOP"
ITEMS = json.loads((ROOT / "tts_input.json").read_text(encoding="utf-8"))
PILOT = json.loads((ROOT / "pilot_text.json").read_text(encoding="utf-8"))
REF = {"ur": (ROOT / "ref_ur.wav", PILOT["ref_ur"]), "en": (ROOT / "ref_en.wav", None)}
RATE = 24000
CHUNK_CHARS = {"ur": 260, "en": 320}
SENTENCE_GAP = np.zeros(int(RATE * 0.30), dtype=np.float32)
PARAGRAPH_GAP = np.zeros(int(RATE * 0.65), dtype=np.float32)
HARAKAT = re.compile(r"[ً-ْٰۖ-ۭ]")


def log(message: str) -> None:
    line = f"[{time.strftime('%F %T')}] {message}"
    print(line, flush=True)
    with (ROOT / "tts_quran.log").open("a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def gpu_temperature() -> int:
    out = subprocess.run(["nvidia-smi", "--query-gpu=temperature.gpu", "--format=csv,noheader,nounits"],
                         capture_output=True, text=True, check=True).stdout
    return int(out.split()[0])


def is_quranic_arabic(sentence: str) -> bool:
    """A vowelled Arabic quotation (the ayah itself), not Urdu prose."""
    letters = sum(ch.isalpha() for ch in sentence)
    return letters > 0 and len(HARAKAT.findall(sentence)) / letters > 0.25


def paragraphs(text: str, voice: str) -> list[list[str]]:
    """Paragraphs of speakable chunks: sentences packed up to CHUNK_CHARS."""
    result = []
    for paragraph in re.split(r"\n\s*\n|\n", text):
        sentences = [s.strip() for s in re.split(r"(?<=[۔؟!.?])\s+", paragraph) if s.strip()]
        sentences = [s for s in sentences if not is_quranic_arabic(s)]
        chunks, current = [], ""
        for sentence in sentences:
            while len(sentence) > CHUNK_CHARS[voice] * 1.6:   # a run-on sentence: break at a comma or space
                cut = max(sentence.rfind("،", 0, CHUNK_CHARS[voice]), sentence.rfind(",", 0, CHUNK_CHARS[voice]),
                          sentence.rfind(" ", 0, CHUNK_CHARS[voice]))
                cut = cut if cut > 40 else CHUNK_CHARS[voice]
                if current:
                    chunks.append(current); current = ""
                chunks.append(sentence[:cut + 1].strip()); sentence = sentence[cut + 1:].strip()
            if current and len(current) + len(sentence) + 1 > CHUNK_CHARS[voice]:
                chunks.append(current); current = sentence
            else:
                current = f"{current} {sentence}".strip()
        if current:
            chunks.append(current)
        if chunks:
            result.append(chunks)
    return result


class Narrator:
    def __init__(self) -> None:
        self.model = OmniVoice.from_pretrained("k2-fsa/OmniVoice", device_map="cuda:0", dtype=torch.float16)
        self.chars_per_second = {"ur": [], "en": []}

    def expected(self, voice: str, text: str) -> float | None:
        samples = self.chars_per_second[voice]
        return len(text) / statistics.median(samples) if len(samples) >= 30 else None

    def say(self, voice: str, text: str) -> tuple[np.ndarray, bool]:
        ref_audio, ref_text = REF[voice]
        kwargs = {"text": text, "ref_audio": str(ref_audio)}
        if ref_text:
            kwargs["ref_text"] = ref_text
        best, best_error = None, None
        for _ in range(3):
            audio = self.model.generate(**kwargs)[0].astype(np.float32)
            seconds = len(audio) / RATE
            expected = self.expected(voice, text)
            if expected is None:
                self.chars_per_second[voice].append(len(text) / max(seconds, 0.1))
                return audio, False
            error = abs(np.log(seconds / expected))
            if best is None or error < best_error:
                best, best_error = audio, error
            if 0.55 * expected <= seconds <= 1.9 * expected:
                self.chars_per_second[voice].append(len(text) / seconds)
                return audio, False
        return best, True


def main() -> int:
    narrator = Narrator()
    flagged_path = ROOT / "flagged.json"
    flagged = json.loads(flagged_path.read_text()) if flagged_path.exists() else {}
    done = skipped = 0
    started = time.monotonic()
    for index, item in enumerate(ITEMS):
        if STOP.exists():
            log("stop requested; leaving off here")
            return 4
        name = f"{item['surah']:03d}{item['ayahStart']:03d}" + (f"-{item['ayahEnd']:03d}" if item["ayahEnd"] != item["ayahStart"] else "")
        target = OUT / item["edition"] / item["kind"] / f"{name}.mp3"
        if target.exists():
            skipped += 1
            continue
        if gpu_temperature() >= 83:
            log("GPU hot, pausing")
            while gpu_temperature() >= 70:
                time.sleep(30)
        pieces, bad = [], False
        for chunks in paragraphs(item["text"], item["voice"]):
            for chunk in chunks:
                audio, flag = narrator.say(item["voice"], chunk)
                bad |= flag
                pieces += [audio, SENTENCE_GAP]
            pieces[-1] = PARAGRAPH_GAP
        if not pieces:                      # nothing speakable (an all-Arabic passage)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        wav = target.with_suffix(".wav")
        sf.write(wav, np.concatenate(pieces[:-1]), RATE)
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(wav), "-ac", "1", "-b:a", "64k", str(target)], check=True)
        wav.unlink()
        if bad:
            flagged[f"{item['edition']}/{item['kind']}/{name}"] = "length far from expected after 3 tries"
            flagged_path.write_text(json.dumps(flagged, indent=1))
        done += 1
        if done % 100 == 0:
            rate = done / (time.monotonic() - started)
            left = len(ITEMS) - index - 1
            log(f"{index + 1}/{len(ITEMS)} ({item['edition']} {item['kind']} {name}); {done} made this run, "
                f"{len(flagged)} flagged, about {left / rate / 3600:.1f} h of items left")
    log(f"all done: {done} made, {skipped} already there, {len(flagged)} flagged")
    return 0


if __name__ == "__main__":
    sys.exit(main())
