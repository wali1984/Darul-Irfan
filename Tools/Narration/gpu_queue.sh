#!/usr/bin/env bash
# Darul Irfan job queue for amd: one job at a time, never two on the GPU.
#
#   1 bayan-download   no GPU   fetch the recordings that failed (spaces in links)
#   2 whisper-setup    no GPU   separate venv + model, never touches urdu-ocr/.venv
#   3 murshid-ocr      GPU      246 Al-Murshid PDFs through the urdu-ocr Surya pipeline
#   4 whisper-pilot    GPU      12 bayans, quality gate before the rest
#   5 whisper-all      GPU      the remaining bayans
#
# A GPU job starts only after the appraisal translation has finished and the
# card has sat idle and cool for 5 minutes. While it runs a watchdog checks the
# card every 20 s and halts everything on a new Xid, a missing power cap, an
# unresponsive driver or 88C. A halt is never retried automatically: after the
# Xid 79 of 2026-10-26 a person should look first. Every job is resumable, so
# after a fix:  rm /mnt/sata1tb/di-queue/HALTED  and start this script again.
#
# Status: tail /mnt/sata1tb/di-queue/queue.log ; per-job output in <job>.log

set -u
Q=/mnt/sata1tb/di-queue
OCR=/mnt/sata1tb/urdu-ocr
BAYANS=/mnt/sata1tb/di-bayans
WHISPER=/mnt/sata1tb/di-whisper
mkdir -p "$Q/done"
exec 9>"$Q/queue.lock"
flock -n 9 || { echo "queue already running"; exit 0; }
[ -f "$Q/HALTED" ] && { echo "queue is halted: $(cat "$Q/HALTED")"; exit 1; }

JOB=
log() { echo "[$(date '+%F %T')] $*" | tee -a "$Q/queue.log"; }
gpu() { nvidia-smi --query-gpu="$1" --format=csv,noheader,nounits | head -1 | tr -d ' '; }
xids() { journalctl -k -b 0 --no-pager 2>/dev/null | grep -c "NVRM: Xid"; }
XID_AT_START=$(xids)

stop_surya() {
  docker ps --filter name=surya-vllm- -q | xargs -r docker stop >/dev/null 2>&1 || true
}

halt() {
  log "HALT: $*"
  echo "$(date '+%F %T') $*" > "$Q/HALTED"
  [ -n "$JOB" ] && kill -TERM -- "-$JOB" 2>/dev/null
  stop_surya
  exit 1
}

check_gpu() {
  nvidia-smi >/dev/null 2>&1 || halt "GPU driver not answering"
  [ "$(xids)" -gt "$XID_AT_START" ] && halt "new GPU fault (Xid) in the kernel log"
  local limit temp
  limit=$(gpu power.limit); temp=$(gpu temperature.gpu)
  [ "${limit%.*}" -gt 300 ] && halt "power cap is ${limit} W, expected 300 W"
  [ "$temp" -ge 88 ] && halt "GPU at ${temp}C"
  return 0
}

wait_for_idle_gpu() {
  local calm=0 said=
  while [ "$calm" -lt 10 ]; do
    # Another GPU job (e.g. the OmniVoice runs) holds the card: step aside;
    # whoever placed the hold relaunches this queue when it is done.
    [ -f "$Q/HALTED" ] && { log "held while waiting: $(cat "$Q/HALTED")"; exit 0; }
    check_gpu
    if pgrep -f translation_gate.py >/dev/null; then
      calm=0; [ -z "$said" ] && { log "waiting for the appraisal translation to finish"; said=1; }
    elif [ "$(gpu memory.used)" -lt 1500 ] && [ "$(gpu utilization.gpu)" -lt 10 ] && [ "$(gpu temperature.gpu)" -lt 65 ]; then
      calm=$((calm + 1))
    else
      calm=0
    fi
    sleep 30
  done
}

# run <name> cpu|gpu command...
run() {
  local name=$1 kind=$2 rc; shift 2
  [ -f "$Q/done/$name" ] && { log "$name already done"; return 0; }
  [ "$kind" = gpu ] && { log "$name: waiting for an idle GPU"; wait_for_idle_gpu; }
  log "$name: started"
  setsid nice -n 10 ionice -c3 "$@" >>"$Q/$name.log" 2>&1 &
  JOB=$!
  while kill -0 "$JOB" 2>/dev/null; do
    [ "$kind" = gpu ] && check_gpu
    sleep 20
  done
  wait "$JOB"; rc=$?; JOB=
  [ "$kind" = gpu ] && stop_surya
  if [ "$rc" -eq 0 ]; then
    touch "$Q/done/$name"; log "$name: finished"
    [ "$kind" = gpu ] && { log "cooling down 5 minutes"; sleep 300; }
    return 0
  fi
  log "$name: exited with $rc"
  return "$rc"
}

# A GPU job can stop because something else (ili-ai's Ollama) took memory; the
# jobs resume where they were, so try up to three times before giving up.
run_with_retries() {
  local attempt
  for attempt in 1 2 3; do
    run "$@" && return 0
    [ "$attempt" -lt 3 ] && { log "$1: retrying in 10 minutes ($attempt/3)"; sleep 600; }
  done
  halt "$1 failed three times, see $Q/$1.log"
}

log "queue started (Xid count this boot: $XID_AT_START)"

run bayan-download cpu python3 "$BAYANS/fetch_bayans.py" || log "bayan-download: some recordings still missing, see $BAYANS/failures.txt"

run_with_retries whisper-setup cpu bash "$Q/whisper_setup.sh"

run_with_retries murshid-ocr gpu env \
  SURYA_INFERENCE_BACKEND=vllm SURYA_INFERENCE_HOST=127.0.0.1 SURYA_INFERENCE_PORT=18080 \
  SURYA_INFERENCE_PARALLEL=4 VLLM_GPU_MEMORY_UTILIZATION=0.72 VLLM_GPU_TYPE=t4 \
  IMAGE_DPI=96 IMAGE_DPI_HIGHRES=192 HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 \
  "$OCR/.venv/bin/python" "$OCR/generic_books_raw_ocr.py" \
    --source-dir "/mnt/sata1tb/Darul Irfan/Al-Murshid Magazine" \
    --output "$OCR/output/al-murshid-raw-v1" --surya "$OCR/.venv/bin/surya_ocr"

WHISPER_ENV=(env HF_HOME="$WHISPER/hf" LD_LIBRARY_PATH="$WHISPER/cuda-libs")
run whisper-pilot gpu "${WHISPER_ENV[@]}" "$WHISPER/.venv/bin/python" "$Q/whisper_bayans.py" --pilot 12
case $? in
  0) ;;
  3) halt "Whisper pilot failed its quality gate, see $BAYANS/pilot-report.json" ;;
  *) halt "Whisper pilot did not run, see $Q/whisper-pilot.log" ;;
esac

run_with_retries whisper-all gpu "${WHISPER_ENV[@]}" "$WHISPER/.venv/bin/python" "$Q/whisper_bayans.py" --all

# The appraisal translation was paused for the narration and Whisper (owner's
# order, 2026-10-28); it resumes last, where it stopped.
run translation-resume cpu bash /home/wali/di-translate/run_translation.sh

log "queue finished: every job is done"
