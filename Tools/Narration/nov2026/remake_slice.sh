#!/usr/bin/env bash
# One slice of the November remake (run by nov_queue.sh as jobs/30-remake-NN):
# make the slice's ayat with tts_higgs_v3.py into quran-v3/, check every file
# with Whisper against its exact text (verify_narration.py, results in
# verify/), remake what fails, up to ROUNDS times. What still fails is listed in
# held_v3.txt for a person to hear. Nothing is uploaded or published here.
#     remake_slice.sh <slice-file> [tts options...]
set -u
N=/mnt/sata1tb/di-voices/nov-fixes
V=/mnt/sata1tb/di-voices
SLICE=$1; shift
ROUNDS=${ROUNDS:-3}
cd "$N"
mkdir -p verify quran-v3
log() { echo "[$(date '+%F %T')] $(basename "$SLICE"): $*" | tee -a "$N/remake.log"; }
up() {
  docker start di-higgs >/dev/null
  for _ in $(seq 1 60); do curl -s -m 5 -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/health | grep -q 200 && return 0; sleep 10; done
  return 1
}
check() {
  local names; names=$(sed 's#.*/##' "$1" | tr '\n' ' ')
  NARRATION_ROOT="$N/quran-v3" VERIFY_DIR="$N/verify" HF_HOME=/mnt/sata1tb/di-whisper/hf \
    LD_LIBRARY_PATH=/mnt/sata1tb/di-whisper/cuda-libs nice /mnt/sata1tb/di-whisper/.venv/bin/python -u \
    "$V/verify_narration.py" translation $names >> "$N/verify/verify.log" 2>&1
}
failing() {
  python3 - "$1" <<'PY'
import json, sys
from pathlib import Path
N = Path("/mnt/sata1tb/di-voices/nov-fixes")
results = json.loads((N / "verify/verify_translation.json").read_text(encoding="utf-8"))
keys = [k for k in Path(sys.argv[1]).read_text().split() if k]
bad = [k for k in keys if results.get(k, {}).get("flag", True)]
print("\n".join(bad))
PY
}
todo=$SLICE
for round in $(seq 0 "$ROUNDS"); do
  [ -s "$todo" ] || break
  log "round $round: making $(wc -l < "$todo") files"
  up || { log "Higgs server did not start"; exit 1; }
  nice /mnt/sata1tb/di-voices/vox/bin/python -u tts_higgs_v3.py --out quran-v3 --keys @"$todo" "$@" >> "$N/remake_tts.log" 2>&1 || { docker stop di-higgs >/dev/null; log "narrator stopped (exit $?)"; exit 1; }
  docker stop di-higgs >/dev/null
  check "$todo"
  failing "$todo" > "$N/verify/failing.tmp"
  log "round $round: $(wc -l < "$N/verify/failing.tmp") failed the check"
  [ "$round" -lt "$ROUNDS" ] && while read -r k; do [ -n "$k" ] && rm -f "quran-v3/$k.mp3"; done < "$N/verify/failing.tmp"
  cp "$N/verify/failing.tmp" "$N/verify/redo_$(basename "$SLICE")"
  todo="$N/verify/redo_$(basename "$SLICE")"
done
if [ -s "$todo" ]; then
  cat "$todo" >> "$N/held_v3.txt"
  log "done; $(wc -l < "$todo") held for a person"
else
  log "done; every file read its text"
fi
exit 0
