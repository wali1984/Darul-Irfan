"""Offline checks of the relay's YouTube broadcast lifecycle (youtube_live.py)
against a fake YouTube API: python tests/test_youtube_live.py"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "relay"))
import youtube_live as yl  # noqa: E402

failures = 0


def check(name, ok, detail=""):
    global failures
    print(f"{'PASS' if ok else 'FAIL'}  {name}{'' if ok else '  ' + detail}")
    failures += 0 if ok else 1


class Fake:
    """YouTube as the relay sees it: streams, broadcasts, transitions."""

    def __init__(self):
        self.stream_status = "ready"
        self.broadcasts: dict[str, dict] = {}
        self.calls: list[tuple[str, str, dict]] = []
        self.next_id = 1

    def call(self, method, path, params=None, body=None):
        params = params or {}
        self.calls.append((method, path, params))
        if path == "liveStreams" and method == "GET":
            if "id" in params:
                return {"items": [{"id": "stream-1", "status": {"streamStatus": self.stream_status, "healthStatus": {"status": "good"}}}]}
            return {"items": [{"id": "stream-1", "snippet": {"title": "ourshiekh"}, "cdn": {"ingestionInfo": {"streamName": "key-abc"}}},
                              {"id": "stream-2", "snippet": {"title": "other"}, "cdn": {"ingestionInfo": {"streamName": "key-xyz"}}}]}
        if path == "liveBroadcasts" and method == "POST":
            bid = f"bc-{self.next_id}"; self.next_id += 1
            self.broadcasts[bid] = {"life": "ready", "body": body, "bound": None}
            return {"id": bid}
        if path == "liveBroadcasts/bind":
            self.broadcasts[params["id"]]["bound"] = params["streamId"]
            return {}
        if path == "liveBroadcasts" and method == "GET" and "broadcastStatus" in params:
            wanted = {"active": ("live", "testing"), "upcoming": ("ready", "created")}[params["broadcastStatus"]]
            return {"items": [{"id": bid, "status": {"lifeCycleStatus": b["life"]}, "contentDetails": {"boundStreamId": b["bound"]},
                               "snippet": {"scheduledStartTime": b.get("sched")}} for bid, b in self.broadcasts.items() if b["life"] in wanted]}
        if path == "liveBroadcasts" and method == "GET":
            b = self.broadcasts.get(params["id"])
            return {"items": [{"status": {"lifeCycleStatus": b["life"]}}]} if b else {"items": []}
        if path == "liveBroadcasts/transition":
            self.broadcasts[params["id"]]["life"] = params["broadcastStatus"]
            return {}
        raise AssertionError(f"unexpected call {method} {path}")


def fresh():
    fake = Fake()
    tmp = Path(tempfile.mkdtemp())
    yl.SESSION_FILE = tmp / "youtube_session.json"
    yt = yl.YouTube("key-abc", "Daily Zikr", "unlisted")
    yt._call = fake.call  # noqa: SLF001
    yt.access_token, yt.token_expires = "t", 9e12
    return yt, fake


# 1. A new session: broadcast made with auto-start/auto-stop, bound to OUR stream.
yt, fake = fresh()
bid = yt.ensure("session-1", "Tahajjud Zikr")
b = fake.broadcasts[bid]
check("broadcast made and bound to the relay's stream", b["bound"] == "stream-1" and b["body"]["snippet"]["title"] == "Tahajjud Zikr"
      and b["body"]["contentDetails"]["enableAutoStart"] and b["body"]["contentDetails"]["enableAutoStop"]
      and b["body"]["status"]["privacyStatus"] == "unlisted", str(b))

# 2. The same session again (a relay restart): the saved broadcast is reused while usable.
yt2 = yl.YouTube("key-abc", "Daily Zikr", "unlisted"); yt2._call = fake.call; yt2.access_token, yt2.token_expires = "t", 9e12  # noqa: SLF001
check("after a restart the session's broadcast is found again", yt2.ensure("session-1") == bid and len(fake.broadcasts) == 1)

# 3. A completed broadcast is not reused: a new one for the same key.
fake.broadcasts[bid]["life"] = "complete"
bid2 = yt2.ensure("session-1")
check("a completed broadcast gives way to a new one", bid2 != bid and len(fake.broadcasts) == 2)

# 4. Another session: a 'ready' broadcast of an earlier session is not reused; a LIVE one on our stream is.
bid3 = yt2.ensure("session-2")
check("a new session gets its own broadcast", bid3 not in (bid, bid2))
fake.broadcasts[bid3]["life"] = "live"
yt3 = yl.YouTube("key-abc", "Daily Zikr", "unlisted"); yt3._call = fake.call; yt3.access_token, yt3.token_expires = "t", 9e12  # noqa: SLF001
yl.SESSION_FILE.unlink(missing_ok=True)
check("a broadcast already live on our stream is adopted", yt3.ensure("session-9") == bid3)

# 5. ready + stream active -> asks for live; ready + stream not active -> stays ready.
yt, fake = fresh()
yt.ensure("s")
fake.stream_status = "ready"
check("no transition while the stream is idle", yt.go_live_if_ready() == "ready")
fake.stream_status = "active"
check("stream active and broadcast ready -> live", yt.go_live_if_ready() == "live")

# 6. complete() ends a live broadcast and forgets it; a second complete is harmless.
yt.complete()
check("complete ends the broadcast and forgets it", fake.broadcasts["bc-1"]["life"] == "complete" and yt.broadcast_id is None
      and not yl.SESSION_FILE.exists())
yt.complete()
check("completing nothing is harmless", True)

# 6b. A broadcast scheduled in Studio on our stream is adopted instead of making a rival; one on another stream is not.
yt, fake = fresh()
fake.broadcasts["studio-1"] = {"life": "ready", "body": None, "bound": "stream-1", "sched": "2026-11-06T23:45:00Z"}
fake.broadcasts["other-1"] = {"life": "ready", "body": None, "bound": "stream-2", "sched": "2026-11-06T20:00:00Z"}
check("a ready Studio event on our stream is NOT adopted (YouTube refuses API transitions on it)",
      yt.ensure("s-adopt") not in ("studio-1", "other-1") and len(fake.broadcasts) == 3)
yt, fake = fresh()
fake.broadcasts["other-1"] = {"life": "ready", "body": None, "bound": "stream-2", "sched": "2026-11-06T20:00:00Z"}
check("a broadcast on another stream is left alone", yt.ensure("s-new") not in ("other-1",) and len(fake.broadcasts) == 2)

# 7. No stream with our key: ensure raises a clear error (the encoder still runs).
yt, fake = fresh()
yt.stream_key = "no-such-key"
try:
    yt.ensure("s")
    check("unknown key raises", False, "no error")
except yl.YouTubeError as error:
    check("unknown key raises", error.status == 404 and "no stream" in str(error), str(error))

print(f"{failures} failure(s)")
sys.exit(failures)
