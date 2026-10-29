#!/usr/bin/env bash
# Every 30 minutes, once the R2 key exists, upload new narrations and the
# manifest; one last upload after the narration run ends, then stop.
R=/mnt/sata1tb/di-tts
log() { echo "[$(date '+%F %T')] $*" >> "$R/upload.log"; }
log "upload loop started"
while :; do
  running=0; pgrep -f "[t]ts_quran.py" >/dev/null && running=1
  if [ -f "$HOME/.config/darul-irfan/r2.env" ]; then
    out=$(nice "$R/.venv/bin/python" "$R/upload_narration.py" 2>&1 | tail -1); log "$out"
  else
    log "waiting for ~/.config/darul-irfan/r2.env (R2 key)"
  fi
  [ "$running" -eq 0 ] && { log "narration not running; last upload done"; break; }
  sleep 1800
done
