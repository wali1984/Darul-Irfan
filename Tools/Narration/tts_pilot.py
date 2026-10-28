#!/usr/bin/env python3
"""Pilot: Akram-ut-Tarajum read aloud with OmniVoice (k2-fsa, Apache-2.0).

Al-Fatiha and Al-Mulk, Urdu in a voice modelled on Shamshad Ali Khan's
recordings and English in a voice modelled on Ibrahim Walk's (everyayah.com,
use confirmed by the owner). One file per ayah plus one per surah to listen to.

Runs only on an idle GPU; gpu_pilot.sh pauses the translation job around it.
"""

from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
from omnivoice import OmniVoice

ROOT = Path("/mnt/sata1tb/di-tts")
OUT = ROOT / "pilot"
TEXT = json.loads((ROOT / "pilot_text.json").read_text(encoding="utf-8"))
REFERENCES = {
    "ur": {"url": "https://everyayah.com/data/translations/urdu_shamshad_ali_khan_46kbps/067001.mp3", "text": TEXT["ref_ur"]},
    # No ref_text: OmniVoice transcribes the English clip itself with Whisper.
    "en": {"url": "https://everyayah.com/data/English/Sahih_Intnl_Ibrahim_Walk_192kbps/067001.mp3", "text": None},
}
GAP = np.zeros(int(24000 * 0.7), dtype=np.float32)


def reference(language: str) -> Path:
    target = ROOT / f"ref_{language}.wav"
    if not target.exists():
        mp3 = target.with_suffix(".mp3")
        subprocess.run(["curl", "-sfL", "--max-time", "60", "-o", str(mp3), REFERENCES[language]["url"]], check=True)
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(mp3), "-ac", "1", "-ar", "24000", str(target)], check=True)
    return target


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    model = OmniVoice.from_pretrained("k2-fsa/OmniVoice", device_map="cuda:0", dtype=torch.float16)
    report = {}
    for language in ("ur", "en"):
        ref = reference(language)
        for surah in (1, 67):
            keys = sorted((k for k in TEXT[language] if k.startswith(f"{surah}:")), key=lambda k: int(k.split(":")[1]))
            pieces, started = [], time.monotonic()
            for key in keys:
                kwargs = {"text": TEXT[language][key], "ref_audio": str(ref)}
                if REFERENCES[language]["text"]:
                    kwargs["ref_text"] = REFERENCES[language]["text"]
                audio = model.generate(**kwargs)[0].astype(np.float32)
                sf.write(OUT / f"{language}_{surah:03d}{int(key.split(':')[1]):03d}.wav", audio, 24000)
                pieces += [audio, GAP]
            surah_audio = np.concatenate(pieces)
            wav = OUT / f"{language}_surah_{surah:03d}.wav"
            sf.write(wav, surah_audio, 24000)
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(wav), "-b:a", "96k", str(wav.with_suffix(".mp3"))], check=True)
            seconds = len(surah_audio) / 24000
            report[f"{language}_{surah}"] = {"ayat": len(keys), "audio_seconds": round(seconds), "took_seconds": round(time.monotonic() - started)}
            print(language, surah, report[f"{language}_{surah}"], flush=True)
    (OUT / "report.json").write_text(json.dumps(report, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
