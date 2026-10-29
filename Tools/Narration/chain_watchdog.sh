#!/usr/bin/env bash
# GPU watchdog for finish_translation.sh (the check, the remakes, the upload):
# the same guards as higgs_run.sh. The card fell off the bus once (Xid 79,
# 2026-10-26); on a new Xid, a silent driver, a missing 300 W cap or 88C the
# chain is stopped, the Higgs server is stopped, and the GPU queue is left
# held with the reason, for a person to look at. Never retried automatically.
set -u
V=/mnt/sata1tb/di-voices
Q=/mnt/sata1tb/di-queue
log() { echo "[$(date '+%F %T')] $*" | tee -a "$V/redo_cycle.log"; }
gpu() { nvidia-smi --query-gpu="$1" --format=csv,noheader,nounits | head -1 | tr -d ' '; }
xids() { journalctl -k -b 0 --no-pager 2>/dev/null | grep -c "NVRM: Xid"; }
XID0=$(xids)
log "watchdog on (Xid count $XID0)"
while pgrep -f "[f]inish_translation.sh" >/dev/null; do
  reason=
  timeout 20 nvidia-smi >/dev/null 2>&1 || reason="GPU driver not answering"
  [ -z "$reason" ] && [ "$(xids)" -gt "$XID0" ] && reason="new GPU fault (Xid)"
  [ -z "$reason" ] && [ "$(gpu power.limit | cut -d. -f1)" -gt 300 ] && reason="power cap missing"
  [ -z "$reason" ] && [ "$(gpu temperature.gpu)" -ge 88 ] && reason="GPU at 88C"
  if [ -n "$reason" ]; then
    touch "$V/STOP"
    pkill -f "[f]inish_translation.sh"; pkill -f "[r]edo_cycle.sh"
    pkill -f "[t]ts_higgs_ur.py"; pkill -f "[v]erify_narration.py"
    docker stop di-higgs >/dev/null 2>&1
    echo "$(date '+%F %T') $reason during the narration check/remake; look before releasing" > "$Q/HALTED"
    log "HALT: $reason"
    exit 1
  fi
  sleep 20
done
log "watchdog off: the chain has ended"
