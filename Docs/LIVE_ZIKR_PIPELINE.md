# Live zikr: one source, every destination, nothing manual

Revised 2026-10-27 after the owner's constraints:

- **Nothing can be installed where the zikr is led.** Hazrat Ji may lead from
  a PC, a laptop or a phone, any of them, at any time.
- **Live only.** Nothing is recorded or replayed.
- **No dependence on any one device.** The system joins, captures and
  delivers on its own.
- **Approved:** Cloudflare Stream at $5 a month.

## The constraint that shapes everything

Paltalk publishes no API and has no browser version: it is an app for
Windows, Mac, iOS and Android only (checked on paltalk.com, 2026-10-27).
Nothing can read a Paltalk room except a Paltalk app that has joined it. With
nothing installable on Hazrat Ji's side, the only device-independent source
is **our own Paltalk listener, running in the cloud**, that joins the room
like any member and carries its sound on.

## Design: two independent cloud listeners, one hub

```
 Hazrat Ji (any device) ──► Paltalk room "OURSHEIKH"
                               │            │
                 listener A ◄──┘            └──► listener B
         (cloud Windows server,                (second cloud Windows server,
          provider 1, Paltalk                   provider 2, own Paltalk
          listener account 1)                   listener account 2)
                 │                                    │
            SRT, live only                       SRT, live only
                 ▼                                    ▼
     Cloudflare Stream input A            Cloudflare Stream input B
       (recording off)                      (recording off)
          ├─► YouTube  primary ingest          ├─► YouTube  backup ingest
          ├─► Facebook primary                 ├─► Facebook backup
          └─► app (fallback player)            └─► app (fallback player)

 Our server (Cloudflare Worker): zikr times, health of both listeners, live
 state for the app and every group, "Daily Zikr has started" notifications,
 alerts to admins when something fails.
```

Each listener is a small Windows server running:

1. **Paltalk** signed in with its own listener account.
2. **The Darul Irfan listener agent**, which:
   - fetches the zikr times from our server;
   - from a few minutes before each window, looks for the room - Paltalk
     lists OURSHEIKH only while a session is running - and joins it the moment
     it appears, muted;
   - captures the room's sound (and the speaker's camera if one is on), puts
     it over a Daily Zikr frame for the video platforms, and streams it live;
   - stops when the room closes;
   - restarts Paltalk or the stream if either stalls, dismisses Paltalk's
     popups, and reports a heartbeat to our server every 30 seconds.

YouTube and Facebook both accept a primary and a backup stream for the same
broadcast. Listener A feeds the primary ingest and listener B the backup, so
either can fail without the broadcast ending. The app plays the YouTube stream
in its own player (free at any number of viewers, no platform named) and
falls back to whichever Cloudflare input is live.

## Failure handling, layer by layer

| What fails | What happens |
|---|---|
| Nobody does anything | Nothing needs doing: the listeners join when the room opens |
| Hazrat Ji switches device mid-session | The room continues; the listeners stay in it |
| One listener server, its provider or its account fails | The other carries the broadcast; admins are told |
| Paltalk's app freezes or shows a popup | The agent restarts or dismisses it within seconds |
| Cloudflare Stream is down | The listeners switch to streaming straight to YouTube and Facebook |
| YouTube is down | The app plays the Cloudflare stream; Facebook continues |
| Both listeners are down | Admins are alerted within 2 minutes of the room opening, on the app and on WhatsApp |
| The room never opens | The app says Daily Zikr has not started yet, never a broken player |

## What it cannot guarantee

As long as the source is Paltalk, one thing stays outside our control:
Paltalk itself. A Paltalk update can change its app, and Paltalk may object
to listener accounts that run unattended. Two listeners on different
providers, constant health checks and alerts make a failure rare and
immediately visible, but no design can promise a Paltalk session that
Paltalk does not let us see. The only fully independent path is the one in
"Later" below.

## Cost

| Item | Monthly |
|---|---|
| Cloudflare Stream (recording off; viewers on the hub only while YouTube is down) | $5 (approved) |
| Two small cloud Windows servers, different providers (2 vCPU, 4 GB; audio only, no GPU needed) | about $15-35 each |
| Two Paltalk listener accounts | free |

## Decisions needed

1. Approval of the two listener servers (about $30-70 a month together), or
   one to start with and the second once the first is proven.
2. Two Paltalk accounts for the listeners (ordinary free accounts).
3. Access to create persistent stream keys on the YouTube channel and the
   Facebook page, with backup ingest enabled.
4. The WhatsApp numbers that receive failure alerts.

## Building it

1. Hub: two Cloudflare Stream live inputs, recording off, simulcast to
   YouTube and Facebook (primary and backup), webhooks for connected and
   disconnected; live state wired to the app and the groups.
2. Listener agent (Windows): room watch and join, capture, stream, self-heal,
   heartbeat; installed as a service so it survives reboots.
3. Monitoring in the Worker: heartbeats, input status, zikr windows; alerts.
4. App: in-app player with automatic fallback between the YouTube stream and
   the hub's inputs.
5. A rehearsal at real zikr times for a week, with one listener deliberately
   switched off, before anyone relies on it.

## Later: no outside dependency at all

If Hazrat Ji ever leads in the app's own room (built in phase 1), the stream
starts from Darul Irfan itself and Paltalk becomes one more audience. Paltalk
cannot receive an outside stream, so Paltalk listeners would still need
Paltalk in parallel.
