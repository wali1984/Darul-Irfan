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
python listener_agent.py --output "srt://<hub input>"   # live
```

## Status (2026-10-27)

| Part | Status |
|---|---|
| Capture what the machine plays (WASAPI loopback) | works |
| Still Daily Zikr frame + live audio as H.264/AAC (YouTube/Facebook-ready) | works (720p, 48 kHz stereo) |
| Encoder restart on failure, silence fill, keys kept out of logs | done |
| Detect "in the room" from Paltalk's window (accessibility tree) | written; to verify during a session |
| Join OURSHEIKH automatically (`paltalk://` link with the room id, or room search) | needs the room observed live once |
| Heartbeat to the server, alerts | agent side done; server endpoint next |
| Cloudflare Stream inputs, simulcast to YouTube/Facebook | needs Stream enabled and keys |
