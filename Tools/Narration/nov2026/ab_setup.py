#!/usr/bin/env python3
"""Fixed sample set, clean reference and the A/B job scripts (CPU only)."""
import json
import subprocess
import sys
from pathlib import Path

N = Path("/mnt/sata1tb/di-voices/nov-fixes")
sys.path.insert(0, str(N))
import numpy as np
import narration_finish_v3 as f

ED = "akram-ut-tarajum-ur/translation/"
AYAT = """001001 001007 002255 002282 112001 112004 002261 003198 041011 053008 036009 015038 077025 023003 074044 053058
002096 002015 002196 011101 002067 002101 002150 006050 002132 007103 003151 018029 055013 067001 024035 094005""".split()
held = sorted(p.stem for p in (N.parent / "held-v1/akram-ut-tafaseer-ur/tafsir").glob("*.mp3"))
items = {f"{i['surah']:03d}{i['ayahStart']:03d}" + (f"-{i['ayahEnd']:03d}" if i["ayahEnd"] != i["ayahStart"] else ""): i
         for i in json.load(open("/mnt/sata1tb/di-tts/tts_input.json", encoding="utf-8")) if i["voice"] == "ur" and i["kind"] == "tafsir"}
sized = sorted((len(items[h]["text"]), h) for h in held if h in items)
print("held tafsir sizes", sized)
take = [h for n, h in sized if 300 <= n <= 1600][:5]
if len(take) < 5:
    take = [h for _, h in sized][:5]
print("tafsir", take)
keys = [ED + a for a in AYAT] + ["akram-ut-tafaseer-ur/tafsir/" + t for t in take]
(N / "sample_keys.txt").write_text("\n".join(keys) + "\n")

(N / "refs").mkdir(exist_ok=True)
ref = N.parent / "refs/ur/002186.wav"
x = f.decode(ref)
x = f.filtered(x, "afftdn=nr=14:nf=-50:tn=1")
x = f.expand(x)
import soundfile as sf
sf.write(N / "refs/002186_clean.wav", x, f.RATE)
print("ref floor before/after", [round(float(20 * np.log10(np.sqrt((a[:int(.3 * f.RATE)] ** 2).mean()) + 1e-9)), 1) for a in (f.decode(ref), x)])

HIG = "docker start di-higgs >/dev/null; for i in $(seq 1 60); do curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/health | grep -q 200 && break; sleep 10; done"
VOX = "/mnt/sata1tb/di-voices/vox/bin/python -u"
WHI = "env HF_HOME=/mnt/sata1tb/di-whisper/hf LD_LIBRARY_PATH=/mnt/sata1tb/di-whisper/cuda-libs /mnt/sata1tb/di-whisper/.venv/bin/python -u"
script = f"""#!/bin/bash
cd {N}
{HIG}
curl -s -m 5 -o /dev/null -w '%{{http_code}}\\n' http://127.0.0.1:8000/health
{VOX} tts_higgs_v3.py --out ab/B-token --keys @sample_keys.txt --mode token || exit 1
{VOX} tts_higgs_v3.py --out ab/C-split --keys @sample_keys.txt --mode split || exit 1
{VOX} tts_higgs_v3.py --out ab/D-low-temp --keys @sample_keys.txt --mode token --temp 0.5 || exit 1
{VOX} tts_higgs_v3.py --out ab/E-oldref --keys @sample_keys.txt --mode token --ref /mnt/sata1tb/di-voices/refs/ur/002186.wav || exit 1
docker stop di-higgs >/dev/null
find ab -name '*.mp3' | sort > scan/ab_files.txt
{WHI} whisper_words.py ur scan/words_ab.jsonl @scan/ab_files.txt
"""
(N / "jobs/15-ab").write_text(script)
(N / "jobs/15-ab").chmod(0o755)
