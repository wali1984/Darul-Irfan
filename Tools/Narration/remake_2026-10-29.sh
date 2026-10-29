#!/usr/bin/env bash
# 2026-10-29, owner: "Remake and replace". Remake the published narrations the
# stricter check flags - a number read twice from its bracketed digits (2:261),
# words from the voice's reference clip (6:63), a phrase said twice (3:17) -
# and check them again. A remake replaces the published file only if it
# passes (upload_higgs.py sends checked files only); one that still fails
# stays as it is live and joins the list held for a person to hear.
# The originals are kept in pre-remake-2026-10-29/.
set -u
V=/mnt/sata1tb/di-voices
cd "$V"
log() { echo "[$(date '+%F %T')] $*" | tee -a "$V/redo_cycle.log"; }
log "remake of $(wc -l < remake_2026-10-29.txt) flagged narrations (digits read twice, inserted words) started"
cp remake_2026-10-29.txt redo.txt
ROUNDS=5 bash redo_cycle.sh
# Held for a person: the ayat held before that were not remade now, and what still fails.
{ grep -vxF -f remake_2026-10-29.txt held_2026-10-29_before.txt; cat redo.txt; } | sort -u > redo.merged && mv redo.merged redo.txt
nice /mnt/sata1tb/di-tts/.venv/bin/python upload_higgs.py 2>&1 | tail -1 | tee -a redo_cycle.log
log "remake finished and published (checked files only); $(grep -cxF -f remake_2026-10-29.txt redo.txt) of the remade still failing; $(wc -l < redo.txt) held for a person"
