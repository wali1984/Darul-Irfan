#!/usr/bin/env bash
# November narration jobs: same rules as gpu_queue.sh (one GPU job at a time,
# the queue's lock, its HALTED file, its watchdog; a halt is never retried).
# Runs each executable in jobs/ in name order and appends done/<name>. A job
# dropped into jobs/ while this runs is picked up next. Stops when none is left.
set -u
Q=/mnt/sata1tb/di-queue
N=/mnt/sata1tb/di-voices/nov-fixes
mkdir -p "$N/jobs" "$N/done"
log() { echo "[$(date '+%F %T')] $*" | tee -a "$N/nov_queue.log"; }
# The queue's lock is held only while a job runs, so the Tajweed evaluation (its
# guard.sh takes the same lock and gives up if busy) gets the card between jobs.
exec 8>"$N/nov_queue.pid.lock"
flock -n 8 || { echo "already running"; exit 0; }
[ -f "$Q/HALTED" ] && { log "HALTED: $(cat "$Q/HALTED")"; exit 1; }
gpu() { nvidia-smi --query-gpu="$1" --format=csv,noheader,nounits | head -1 | tr -d ' '; }
xids() { journalctl -k -b 0 --no-pager 2>/dev/null | grep -c "NVRM: Xid"; }
XID0=$(xids)
JOB=
halt() {
  log "HALT: $*"
  echo "$(date '+%F %T') nov-fixes: $*" > "$Q/HALTED"
  [ -n "$JOB" ] && kill -TERM -- "-$JOB" 2>/dev/null
  docker stop di-higgs >/dev/null 2>&1
  exit 1
}
check() {
  nvidia-smi >/dev/null 2>&1 || halt "GPU driver not answering"
  [ "$(xids)" -gt "$XID0" ] && halt "new GPU fault (Xid) in the kernel log"
  local l t; l=$(gpu power.limit); t=$(gpu temperature.gpu)
  [ "${l%.*}" -gt 300 ] && halt "power cap is ${l} W, expected 300 W"
  [ "$t" -ge 88 ] && halt "GPU at ${t}C"
  [ -f "$Q/HALTED" ] && { log "HALTED appeared: stopping job"; [ -n "$JOB" ] && kill -TERM -- "-$JOB" 2>/dev/null; docker stop di-higgs >/dev/null 2>&1; exit 1; }
  return 0
}
# Idle: little memory held, no load, cool, no other compute process (the Tajweed
# evaluation or anyone else's work) for 5 minutes.
idle() {
  local calm=0 said=
  while [ "$calm" -lt 10 ]; do
    check
    if [ "$(gpu memory.used)" -lt 1500 ] && [ "$(gpu utilization.gpu)" -lt 10 ] && [ "$(gpu temperature.gpu)" -lt 65 ] && ! pgrep -f "/mnt/sata1tb/di-tajweed/venv/bin/python.*(eval|muaalem|score)" >/dev/null; then
      calm=$((calm + 1))
    else
      calm=0; [ -z "$said" ] && { log "waiting for the card (another job holds it)"; said=1; }
    fi
    sleep 30
  done
}
log "started (Xid count this boot: $XID0)"
while :; do
  next=
  for f in "$N"/jobs/*; do
    [ -x "$f" ] || continue
    [ -f "$N/done/$(basename "$f")" ] || { next=$f; break; }
  done
  [ -z "$next" ] && { log "no job left"; exit 0; }
  name=$(basename "$next")
  idle
  exec 9>>"$Q/queue.lock"
  until flock -n 9; do log "lock held by another job; waiting"; sleep 120; idle; done
  log "$name: started"
  setsid nice -n 10 ionice -c3 "$next" 9>&- 8>&- >>"$N/$name.log" 2>&1 &
  JOB=$!
  while kill -0 "$JOB" 2>/dev/null; do check; sleep 20; done
  wait "$JOB"; rc=$?; JOB=
  docker stop di-higgs >/dev/null 2>&1
  flock -u 9; exec 9>&-
  if [ "$rc" -eq 0 ]; then
    touch "$N/done/$name"; log "$name: finished"; sleep 300
  else
    # Not a card fault: leave the card to others and do not loop on it.
    log "$name: exited with $rc; stopping here for a look"
    exit "$rc"
  fi
done
