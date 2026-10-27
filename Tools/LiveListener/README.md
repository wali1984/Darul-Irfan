# Live listener

Carries the Paltalk zikr room to the stream hub with nothing installed on
Hazrat Ji's side. Design and failure handling: `Docs/LIVE_ZIKR_PIPELINE.md`.

## Listener PC (Windows)

1. A Windows account for the listener, with Paltalk Desktop signed in to a
   **listener Paltalk account** (not a personal one). Windows volume can stay
   muted: the agent records the sound before Windows applies the volume.
2. `listener.env` beside these files (never committed):

   ```
   OUTPUT=srt://<hub input from Cloudflare Stream>
   INPUT_ID=<that live input's uid>
   LISTENER_ID=listener-a
   HEARTBEAT_URL=https://darul-irfan-platform.wajidmahmoodali1984-e23.workers.dev/v1/live/listener
   LISTENER_TOKEN=<the Worker's LISTENER_TOKEN>
   ```

   Use the workers.dev host: the custom domain answers scripts with a
   Cloudflare challenge page.
3. In that account, from this folder:
   `powershell -ExecutionPolicy Bypass -File install_listener.ps1`.
   It checks for Python, ffmpeg and Paltalk, installs the three Python
   packages, and registers the scheduled task **Darul Irfan Listener**: it
   starts at sign-in and restarts within a minute if it stops. Output goes to
   `listener.log` here.

Set Windows to sign the listener account in automatically, and keep the PC
from sleeping, so it is in the room whenever the session opens.

## Run by hand

```
python listener_agent.py --once-test 20      # 20 s of whatever is playing, to test_stream.ts
python listener_agent.py                     # with listener.env, as the task runs it
```

Every setting in `listener.env` can also be given as a flag (`--output`,
`--input-id`, `--listener-id`, `--heartbeat-url`, `--heartbeat-token`, `--room`).

## Status (2026-10-27)

| Part | Status |
|---|---|
| Capture what the PC plays (WASAPI loopback), level logged each minute | works; full level with Windows muted (peak 30937 of 32767 at volume 0) |
| Still Daily Zikr frame + live audio as H.264/AAC (YouTube/Facebook-ready) | works; 10.5 min of the live room recorded |
| Detect the joined room | works: the room panel plus its topic line (the room name is drawn as a picture) |
| Join: room search every 30 s (a room is listed only while open), open its tile | written; searches only after 20 s without keyboard or mouse use, and hands focus back; first unattended join on the listener PC |
| Room speaker off in Paltalk | pressed automatically when someone is talking and nothing is heard; alert after three tries |
| Encoder restart on failure, silence fill, keys kept out of logs and command lines | done |
| Paltalk not running or hidden in the tray -> started or reopened, and reported | done |
| Heartbeat with problem reports; server alerts admins (push + WhatsApp) | done, server tested; live after the deploy |
| Starts at sign-in, restarts if it stops | `install_listener.ps1` |
| Cloudflare Stream inputs, simulcast to YouTube/Facebook | needs the Stream keys |
