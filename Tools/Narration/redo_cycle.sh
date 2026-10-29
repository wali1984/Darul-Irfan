#!/usr/bin/env bash
# Remake the Urdu narrations in redo.txt and check each again, until every one
# reads its text exactly or ROUNDS tries are used up (owner, 2026-10-28: no
# room for error). Higgs and Whisper do not fit on the card together, so each
# round makes the files with the Higgs server up, then stops it and checks
# them with Whisper. What still fails after the last round stays in redo.txt,
# unpublished, for a person to hear. The GPU queue stays held throughout.
set -u
V=/mnt/sata1tb/di-voices
ROUNDS=${ROUNDS:-5}
log() { echo "[$(date '+%F %T')] $*" | tee -a "$V/redo_cycle.log"; }
healthy() { curl -s -m 5 -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/health | grep -q 200; }
cd "$V"
for round in $(seq 1 "$ROUNDS"); do
  [ -s redo.txt ] || { log "nothing left to remake"; break; }
  names=$(sed 's#.*/##' redo.txt | tr '\n' ' ')
  log "round $round: remaking $(wc -l < redo.txt) files"
  cp redo.txt redo_round.txt
  docker start di-higgs >/dev/null
  for _ in $(seq 1 60); do healthy && break; sleep 10; done
  healthy || { log "HALT: Higgs server did not start"; exit 1; }
  nice "$V/vox/bin/python" -u tts_higgs_ur.py --redo >> higgs_ur.stdout 2>&1
  docker stop di-higgs >/dev/null
  # Check what was remade; anything that fails goes back on the list.
  nice /mnt/sata1tb/di-whisper/.venv/bin/python -u verify_narration.py translation $names >> verify_translation.log 2>&1
  python3 - <<'PY'
import json
from pathlib import Path
V = Path("/mnt/sata1tb/di-voices")
results = json.loads((V / "verify_translation.json").read_text(encoding="utf-8"))
tried = [line for line in (V / "redo_round.txt").read_text().split() if line]
failing = [key for key in tried if results.get(key, {}).get("flag", True)]
(V / "redo.txt").write_text("".join(f"{key}\n" for key in failing))
print(f"{len(tried) - len(failing)} now read exactly, {len(failing)} to try again")
PY
  log "round $round done: $(wc -l < redo.txt) still failing"
done
log "finished; $(wc -l < redo.txt) held back for a person to hear"
