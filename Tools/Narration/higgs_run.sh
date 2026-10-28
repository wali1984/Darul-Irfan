#!/usr/bin/env bash
# Owner's order (2026-10-28): Higgs TTS 3 narrates the Urdu translation, then
# the Urdu tafsir; Whisper and the appraisal translation follow. The GPU queue
# stays held (HALTED) while this runs; a watchdog stops it on a new GPU fault, a
# missing 300 W cap, a silent driver or 88C and leaves the queue held for a
# person to look. On success it stops the Higgs server and releases the queue.
set -u
V=/mnt/sata1tb/di-voices
Q=/mnt/sata1tb/di-queue
log() { echo "[$(date '+%F %T')] $*" | tee -a "$V/higgs_run.log"; }
gpu() { nvidia-smi --query-gpu="$1" --format=csv,noheader,nounits | head -1 | tr -d ' '; }
xids() { journalctl -k -b 0 --no-pager 2>/dev/null | grep -c "NVRM: Xid"; }
healthy() { curl -s -m 5 -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/health | grep -q 200; }
XID0=$(xids)
rm -f "$V/STOP"
echo "$(date '+%F %T') held: Urdu narration with Higgs (higgs_run.sh) runs first" > "$Q/HALTED"

start_server() {
  docker start di-higgs >/dev/null 2>&1 || docker run -d --name di-higgs --gpus all --ipc host --network host --shm-size 16g \
    -v "$V:$V" --entrypoint bash lmsysorg/sglang-omni:dev "$V/higgs_serve.sh" serve >/dev/null
  for _ in $(seq 1 60); do healthy && return 0; sleep 10; done
  return 1
}
healthy || start_server || { log "HALT: Higgs server did not start"; echo "$(date '+%F %T') Higgs server did not start" > "$Q/HALTED"; exit 1; }

attempt=0
while :; do
  cd "$V" && nice "$V/vox/bin/python" -u tts_higgs_ur.py >> "$V/higgs_ur.stdout" 2>&1 &
  JOB=$!
  log "narration started (pid $JOB)"
  while kill -0 "$JOB" 2>/dev/null; do
    reason=
    nvidia-smi >/dev/null 2>&1 || reason="GPU driver not answering"
    [ -z "$reason" ] && [ "$(xids)" -gt "$XID0" ] && reason="new GPU fault (Xid)"
    [ -z "$reason" ] && [ "$(gpu power.limit | cut -d. -f1)" -gt 300 ] && reason="power cap missing"
    [ -z "$reason" ] && [ "$(gpu temperature.gpu)" -ge 88 ] && reason="GPU at 88C"
    if [ -n "$reason" ]; then
      touch "$V/STOP"; kill -TERM "$JOB" 2>/dev/null; docker stop di-higgs >/dev/null 2>&1
      echo "$(date '+%F %T') $reason during Higgs narration; look before releasing" > "$Q/HALTED"
      log "HALT: $reason"; exit 1
    fi
    sleep 20
  done
  wait "$JOB"; rc=$?
  log "narration exited with $rc"
  [ "$rc" -eq 0 ] && break
  [ "$rc" -eq 4 ] && { log "stopped on request; queue stays held"; exit 4; }
  # A server error (out of memory, a crash) ends the script; the server is
  # restarted and the run resumes where it was, three times at most.
  attempt=$((attempt + 1))
  [ "$attempt" -ge 3 ] && { echo "$(date '+%F %T') Higgs narration failed 3 times; see $V/higgs_ur.stdout" > "$Q/HALTED"; log "HALT: failed 3 times"; exit 1; }
  docker restart di-higgs >/dev/null 2>&1; sleep 30
  for _ in $(seq 1 60); do healthy && break; sleep 10; done
done

docker stop di-higgs >/dev/null 2>&1
rm -f "$Q/HALTED"
cd "$Q" && nohup setsid bash gpu_queue.sh >/dev/null 2>&1 < /dev/null &
log "queue released: Whisper next, then the appraisal translation"
