#!/usr/bin/env bash
# After the translation chain (finish_translation.sh): remake the Urdu
# narrations whose text changed when the Urdu Akram-ut-Tarajum was set to the
# 2020 printed edition (text_corrections.json), together with anything the
# chain left failing, check them (redo_cycle.sh), then lift the upload hold
# and publish only what passed. One GPU job at a time: waits for the chain.
set -u
V=/mnt/sata1tb/di-voices
log() { echo "[$(date "+%F %T")] $*" | tee -a "$V/redo_cycle.log"; }
cd "$V"
while pgrep -f "[f]inish_translation.sh" >/dev/null || pgrep -f "[r]edo_cycle.sh" >/dev/null \
      || pgrep -f "[v]erify_narration.py" >/dev/null || pgrep -f "[t]ts_higgs_ur.py" >/dev/null; do sleep 120; done
[ -e HALTED ] && { log "HALTED present: corrections redo not started"; exit 1; }
# The stored transcripts are scored again against the corrected texts first.
/mnt/sata1tb/di-whisper/.venv/bin/python verify_narration.py translation --rescore | tail -2 | tee -a redo_cycle.log
python3 - <<"PY"
import json
from pathlib import Path
V = Path("/mnt/sata1tb/di-voices")
corrected = json.loads((V / "text_corrections.json").read_text(encoding="utf-8"))
key = lambda s, a: f"akram-ut-tarajum-ur/translation/{int(s):03d}{int(a):03d}"
redo = {line for line in (V / "redo.txt").read_text().split() if line} if (V / "redo.txt").exists() else set()
results = json.loads((V / "verify_translation.json").read_text(encoding="utf-8"))
redo |= {k for k, r in results.items() if r.get("flag")}
redo |= {key(*k.split(":")) for k in corrected}
(V / "redo.txt").write_text("".join(f"{k}\n" for k in sorted(redo)))
print(f"to remake: {len(redo)} ({len(corrected)} corrected texts)")
PY
log "2020-print corrections: $(wc -l < redo.txt) files to remake"
ROUNDS=5 bash redo_cycle.sh
rm -f HOLD_UPLOAD
nice /mnt/sata1tb/di-tts/.venv/bin/python upload_higgs.py 2>&1 | tail -1 | tee -a redo_cycle.log
log "2020-print narration finished and published (checked files only); $(wc -l < redo.txt) held for a person"
