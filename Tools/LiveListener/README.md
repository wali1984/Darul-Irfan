# Live listener (prototype)

Carries the Paltalk zikr room to the stream hub with nothing installed on
Hazrat Ji's side. Design and failure handling: `Docs/LIVE_ZIKR_PIPELINE.md`.

## Requirements (listener machine, Windows)

- Paltalk Desktop, signed in with a **listener account** (not a personal one).
- Python 3.12 with `pywinauto==0.6.9 PyAudioWPatch==0.2.12.7 psutil==6.1.1`.
- ffmpeg 9 on PATH (`winget install Gyan.FFmpeg`).

## Run

```
python listener_agent.py --once-test 20                 # local test file
python listener_agent.py --output "srt://<hub input>" --input-id <input uid>     --listener-id listener-a --heartbeat-url https://api.naqshbandiaowaisiah.us/v1/live/listener     --heartbeat-token <LISTENER_TOKEN>
```

## Status (2026-10-27)

| Part | Status |
|---|---|
| Capture what the machine plays (WASAPI loopback), level logged each minute | works |
| Still Daily Zikr frame + live audio as H.264/AAC (YouTube/Facebook-ready) | works (720p, 48 kHz stereo) |
| Encoder restart on failure, silence fill, keys kept out of logs | done |
| Paltalk not running -> started again and reported | done |
| Join: room search every 30 s (a room is listed only while open), open its tile | written; Paltalk search verified; first live join at the 2026-10-27 session |
| Detect "in the room" (its window, pane or tab) | written; to verify at that session |
| Heartbeat with problem reports; server alerts admins (push + WhatsApp) | done, server tested; needs the deploy |
| Cloudflare Stream inputs, simulcast to YouTube/Facebook | needs Stream enabled and keys |

On a PC someone is using, the search briefly brings Paltalk to the front to
press Enter; on a dedicated listener this does not matter.
