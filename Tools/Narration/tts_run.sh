#!/usr/bin/env bash
# Owner's order (2026-10-28): narrate all the Qur'an translations and tafsir
# first, then Whisper, then the appraisal translation resumes.
# The GPU queue stays held (HALTED) while this runs; a watchdog stops the run on
# a new GPU fault, a missing 300 W cap, a silent driver or 88C, and leaves the
# queue held for a person to look. On success it releases the queue.
set -u
R=/mnt/sata1tb/di-tts
Q=/mnt/sata1tb/di-queue
log() { echo "[$(date '+%F %T')] $*" | tee -a "$R/tts_run.log"; }
gpu() { nvidia-smi --query-gpu="$1" --format=csv,noheader,nounits | head -1 | tr -d ' '; }
xids() { journalctl -k -b 0 --no-pager 2>/dev/null | grep -c "NVRM: Xid"; }
XID0=$(xids)
rm -f "$R/STOP"
echo "$(date '+%F %T') held: Qur'an translation/tafsir narration (tts_run.sh) runs first" > "$Q/HALTED"

cd "$R" && HF_HOME="$R/hf" nice .venv/bin/python -u tts_quran.py >> "$R/tts_quran.stdout" 2>&1 &
JOB=$!
log "narration started (pid $JOB)"
while kill -0 "$JOB" 2>/dev/null; do
  reason=
  nvidia-smi >/dev/null 2>&1 || reason="GPU driver not answering"
  [ -z "$reason" ] && [ "$(xids)" -gt "$XID0" ] && reason="new GPU fault (Xid)"
  [ -z "$reason" ] && [ "$(gpu power.limit | cut -d. -f1)" -gt 300 ] && reason="power cap missing"
  [ -z "$reason" ] && [ "$(gpu temperature.gpu)" -ge 88 ] && reason="GPU at 88C"
  if [ -n "$reason" ]; then
    touch "$R/STOP"; kill -TERM "$JOB" 2>/dev/null
    echo "$(date '+%F %T') $reason during narration; look before releasing" > "$Q/HALTED"
    log "HALT: $reason"; exit 1
  fi
  sleep 20
done
wait "$JOB"; rc=$?
log "narration exited with $rc"
[ "$rc" -eq 0 ] || { echo "$(date '+%F %T') narration exited $rc; see $R/tts_quran.stdout" > "$Q/HALTED"; exit "$rc"; }
rm -f "$Q/HALTED"
cd "$Q" && nohup setsid bash gpu_queue.sh >/dev/null 2>&1 < /dev/null &
log "queue released: Whisper next, then the appraisal translation"
