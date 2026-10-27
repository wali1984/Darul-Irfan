# Live zikr: one source, every destination, nothing manual

Proposal for decision, 2026-10-27.

## Today

Hazrat Ji leads the zikr in the Paltalk room "OURSHEIKH". Separately, someone
starts a YouTube Live and a Facebook Live by hand. If that person is late or
something fails, viewers outside Paltalk get nothing, and nobody is told.

## The constraint that shapes everything

Paltalk publishes no API, and its support is limited. Nothing outside Paltalk
can start, read or receive a Paltalk room programmatically. The only way to
take a Paltalk session's sound elsewhere is to capture it from a computer
running the Paltalk app: either the computer the zikr is led from, or a
second computer that joins as a listener.

## Recommendation: capture at the source, fan out through one hub

```
 Hazrat Ji's mic ─┬─► Paltalk (unchanged, room OURSHEIKH)
                  │
                  └─► Encoder on the same PC (OBS) ──SRT──► Cloudflare Stream (hub)
                          │                                     ├──► YouTube Live   (automatic)
                          │                                     ├──► Facebook Live  (automatic)
                          │                                     └──► App (in-app player, fallback)
                          └──RTMP backup──────────────────────► YouTube (direct, if the hub fails)

 Live Agent (small program on the same PC)
   - knows the zikr times from our server
   - sees the Paltalk room open (window "OURSHEIKH") and sound on the mic
   - starts the encoder, restarts it if it crashes, stops it after the room closes
   - reports a heartbeat to our server every 30 s

 Our server (Cloudflare Worker)
   - hears "stream connected" from the hub -> marks Daily Zikr live everywhere,
     pushes "Daily Zikr has started" to the app
   - 3 minutes into a zikr window with nothing live -> alerts the admins
     (app notification and a WhatsApp message from the Business number)
```

Why this, and not a Paltalk bot on a server:

| | Capture at the source (recommended) | Paltalk listener bot on a VPS |
|---|---|---|
| Sound quality | Original microphone, encoded once | Paltalk's compressed audio, re-encoded |
| Moving parts | One PC that is already on for the zikr | A second, unattended Windows machine logging in to Paltalk |
| Breaks when | The zikr PC loses internet (Paltalk breaks too) | Paltalk changes its app, asks for a login or captcha, shows a popup, or flags the account |
| Paltalk terms | Not involved | Automating a client account is at risk of a ban |
| Cost | Nothing extra on the PC | A Windows VPS, about $30-60 a month |

The bot stays as the fallback for a session led from a machine where nothing
can be installed.

## Failure handling, layer by layer

| What fails | What happens |
|---|---|
| Nobody starts it | The Live Agent starts it when the room opens in a zikr window |
| Encoder crashes | The agent restarts it within seconds |
| Cloudflare hub unreachable | The encoder's direct backup keeps YouTube live; the app plays YouTube |
| YouTube rejects the stream | Facebook and the app still receive it from the hub |
| The zikr PC's internet drops | A phone at Dar-ul-Irfan on mobile data, with a broadcast app preset to the hub's backup input, takes over with one tap; the server switches to whichever input is connected |
| Nothing is live 3 min into a window | Admins are alerted on the app and by WhatsApp |
| Everything above fails | The app says Daily Zikr has not started yet, never a broken player; the recording is posted when it arrives |

## How the app plays it

The app plays the YouTube live stream in its own player at any number of
viewers for free, and names no platform. It switches to the hub's own stream
automatically if the YouTube stream is unavailable, so viewers keep watching.
Members who want to join the zikr together use the group room built in phase 1.

## Cost (Cloudflare Stream)

- Sending the stream in and fanning it out: free ingest, up to 50
  destinations per input (simulcast pricing is not published; confirm before
  committing).
- Recording: $5 per 1,000 minutes stored. Two 45-minute sessions a day is
  about 2,700 minutes a month: about $14 a month, less if recordings older
  than 30 days are deleted (they stay on YouTube).
- Viewers on the hub's own stream: $1 per 1,000 minutes watched, but only
  while YouTube is down, because the app plays YouTube first.

## Later: lead the zikr in the app

Once members are used to the app, Hazrat Ji could lead in the app's own room,
which can push the same stream to the hub, making Paltalk optional. Paltalk
cannot receive an outside stream, so it would continue only in parallel.

## Decisions needed

1. Which computer is the zikr led from, and is it Windows or Mac? Who can
   install the encoder and the Live Agent on it?
2. Access to the YouTube channel and Facebook page to create persistent stream
   keys (a key that never changes, so nothing has to be set up per session).
3. Approval of the Cloudflare Stream subscription (from $5 a month).
4. Who should receive the "nothing is live" alert, by WhatsApp number.

## Building it

1. Hub: a Cloudflare Stream live input with primary and backup, simulcast to
   YouTube and Facebook, recording on; Worker webhook for connected and
   disconnected events; live state wired to the app and the groups.
2. Monitoring: zikr-window watch in the Worker's existing 5-minute cron,
   tightened to every minute inside windows; alerts.
3. Live Agent: a small Windows program (and a Mac version if needed) using
   OBS's built-in websocket control; it runs at login, watches for the room
   and the mic, and keeps the encoder alive.
4. App: in-app player with automatic fallback between the YouTube stream and
   the hub's own.
5. A full rehearsal at a real zikr time before anyone relies on it.
