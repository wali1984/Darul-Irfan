#!/usr/bin/env python3
"""VoxCPM2 (Apache-2.0) on Urdu, for the comparison only: Urdu is not among its
30 listed languages (Hindi is). Same reference voice, clause pauses as commas,
same finishing. Writes ab/F-voxcpm2/<edition>/translation/<name>.mp3"""
import os
import re
import sys
from pathlib import Path

import numpy as np

sys.argv, ARGV = sys.argv[:1], sys.argv[1:]
sys.path.insert(0, "/mnt/sata1tb/di-voices/nov-fixes")
import tts_higgs_v3 as t  # noqa: E402
from voxcpm import VoxCPM  # noqa: E402

N = Path("/mnt/sata1tb/di-voices/nov-fixes")
keys = [k for k in (N / "sample_keys.txt").read_text().split() if "/translation/" in k][:12]
model = VoxCPM.from_pretrained("openbmb/VoxCPM2", load_denoiser=False)
rate = model.tts_model.sample_rate
ref = str(N / "refs/002186_clean.wav")
for item in t.base.ITEMS:
    name = f"{item['surah']:03d}{item['ayahStart']:03d}"
    key = f"{item['edition']}/translation/{name}"
    if item["kind"] != "translation" or key not in keys:
        continue
    out = N / "ab/F-voxcpm2" / f"{key}.mp3"
    if out.exists():
        continue
    pieces = []
    for seg in t.base.script(item):
        if "say" in seg:
            text = re.sub(r"\s*\|\s*", "، ", seg["say"]).strip("، ")
            audio = np.asarray(model.generate(text=text, prompt_wav_path=ref, prompt_text=t.base.REF_TEXT,
                                              reference_wav_path=ref, cfg_value=2.0, inference_timesteps=16), dtype=np.float32)
            pieces += [audio, np.zeros(int(rate * .6), np.float32)]
    body = np.concatenate(pieces[:-1])
    body = np.interp(np.linspace(0, len(body) - 1, int(len(body) * t.finishing.RATE / rate)), np.arange(len(body)), body).astype(np.float32)
    t.finishing.encode(t.finishing.finish(body), out)
    print("made", key, flush=True)
