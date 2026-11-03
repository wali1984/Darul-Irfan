#!/usr/bin/env python3
"""Word-timed Whisper over a list of files; resumable JSONL, one file a line:
{"file":..., "words":[[start,end,word],...]}

    whisper_words.py <language> <out.jsonl> <@list|files...>
"""
import json
import os
import subprocess
import sys
from pathlib import Path

import numpy as np

os.environ.setdefault("HF_HOME", "/mnt/sata1tb/di-whisper/hf")
from faster_whisper import WhisperModel  # noqa: E402

lang, out = sys.argv[1], Path(sys.argv[2])
files = []
for a in sys.argv[3:]:
    files += Path(a[1:]).read_text().split("\n") if a.startswith("@") else [a]
files = [f for f in files if f]
done = set()
if out.exists():
    for line in out.read_text(encoding="utf-8").splitlines():
        done.add(json.loads(line)["file"])
todo = [f for f in files if f not in done]
print(len(todo), "to do", flush=True)
model = WhisperModel("large-v3", device="cuda", compute_type="float16")
with out.open("a", encoding="utf-8") as sink:
    for count, f in enumerate(todo, 1):
        raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", f, "-f", "f32le", "-ac", "1", "-ar", "16000", "-"],
                             capture_output=True, check=True).stdout
        segs, _ = model.transcribe(np.frombuffer(raw, np.float32), language=lang, beam_size=5, temperature=0.0,
                                   condition_on_previous_text=False, vad_filter=False, word_timestamps=True)
        words = [[round(w.start, 2), round(w.end, 2), w.word.strip()] for s in segs for w in (s.words or [])]
        sink.write(json.dumps({"file": f, "words": words}, ensure_ascii=False) + "\n")
        sink.flush()
        if count % 100 == 0:
            print(count, "done", flush=True)
print("done", flush=True)
