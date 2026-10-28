# Claude re-read of scanned book pages

`claude_ocr.py` (pilot) and `claude_ocr_run.py` (full run, budget-capped,
resumable) run on amd in `/mnt/sata1tb/di-claude-ocr/`. Results are imported with
`Tools/Library/ingest_claude_pages.py --exclude <suspect pages>`. See the memory
note on the 2026-10-28 run: $199 for 7,880 pages; 1,195 Asrar Urdu pages and 74
incomplete pages are left for the next month.
