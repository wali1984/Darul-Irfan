#!/usr/bin/env bash
# After the full check of the Urdu translation narrations: remake every file
# that does not read its text exactly, every ayah whose text was corrected
# against the printed book, and the ayat that open with disjointed letters;
# check them again (redo_cycle.sh), then publish only what passed.
set -u
V=/mnt/sata1tb/di-voices
log() { echo "[$(date '+%F %T')] $*" | tee -a "$V/redo_cycle.log"; }
cd "$V"
while pgrep -f "[v]erify_narration.py translation$" >/dev/null; do sleep 60; done
/mnt/sata1tb/di-whisper/.venv/bin/python verify_narration.py translation --rescore | tee -a redo_cycle.log
python3 - <<'PY'
import json, sys
from pathlib import Path
V = Path("/mnt/sata1tb/di-voices")
sys.path.insert(0, str(V))
from urdu_spoken import LETTER_AYAT
results = json.loads((V / "verify_translation.json").read_text(encoding="utf-8"))
corrected = json.loads((V / "text_corrections.json").read_text(encoding="utf-8"))
key = lambda s, a: f"akram-ut-tarajum-ur/translation/{s:03d}{a:03d}"
redo = {k for k, r in results.items() if r["flag"]}
redo |= {key(*map(int, k.split(":"))) for k in corrected}
redo |= {key(s, a) for s, a in LETTER_AYAT}
missing = [k for k in redo if not (V / "quran-higgs" / f"{k}.mp3").exists()]
(V / "redo.txt").write_text("".join(f"{k}\n" for k in sorted(redo)))
print(f"to remake: {len(redo)} ({sum(r['flag'] for r in results.values())} failed the check, "
      f"{len(corrected)} corrected texts, {len(LETTER_AYAT)} letter ayat; {len(missing)} without a file)")
PY
log "redo list: $(wc -l < redo.txt) files"
ROUNDS=5 bash redo_cycle.sh
nice /mnt/sata1tb/di-tts/.venv/bin/python upload_higgs.py 2>&1 | tail -1 | tee -a redo_cycle.log
log "translation narration finished and published (checked files only)"
