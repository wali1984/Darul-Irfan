"""YouTube's side of the programme: one broadcast per Zikr session, bound to
the channel's stream key, started when the encoder's picture arrives and
completed when the session ends (audit PR6, 2026-11-06).

Before this the encoder only pushed to the stream key and hoped a broadcast
would pick it up; on 6 November YouTube held a webcam broadcast "upcoming"
all evening and nothing ever went live. Now the relay creates the broadcast
itself through the YouTube Data API and watches its lifecycle:

    ensure(title)  -> the broadcast id for this session (reused after a restart)
    check()        -> ("live" | "ready" | "testing" | "complete" | ..., stream health)
    complete()     -> ends the broadcast (auto-stop would, 5 minutes after the dua, too)

Credentials: the Desktop-app OAuth client (youtube-oauth-client.json) and the
refresh token from one consent (youtube-token.json, made by youtube_auth.py),
both beside the relay and never in git. Only the standard library is used.
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
CLIENT_FILE = HERE / "youtube-oauth-client.json"
TOKEN_FILE = HERE / "youtube-token.json"
SESSION_FILE = HERE / "youtube_session.json"  # the broadcast made for the running session
API = "https://www.googleapis.com/youtube/v3"
SCOPE = "https://www.googleapis.com/auth/youtube"
USER_AGENT = "DarulIrfanRelay/1.0"


def log(message: str) -> None:
    print(f"{time.strftime('%H:%M:%S')} [youtube] {message}", flush=True)


class YouTubeError(Exception):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(f"{status}: {message}")
        self.status = status


def _client() -> dict:
    data = json.loads(CLIENT_FILE.read_text(encoding="utf-8"))
    return data.get("installed") or data.get("web") or {}


class YouTube:
    """A thin client: the token kept fresh, JSON in and out, keys never logged."""

    def __init__(self, stream_key: str, title: str, privacy: str = "public", description: str = "") -> None:
        self.stream_key = stream_key
        self.title = title
        self.privacy = privacy if privacy in ("public", "unlisted", "private") else "public"
        self.description = description
        self.access_token = ""
        self.token_expires = 0.0
        self.stream_id: str | None = None
        self.broadcast_id: str | None = None
        self.session_key: str | None = None
        self.last_error = ""

    @property
    def configured(self) -> bool:
        return CLIENT_FILE.exists() and TOKEN_FILE.exists() and bool(self.stream_key)

    # MARK: - Tokens

    def _refresh(self) -> None:
        client = _client()
        token = json.loads(TOKEN_FILE.read_text(encoding="utf-8"))
        body = urllib.parse.urlencode({
            "client_id": client["client_id"], "client_secret": client["client_secret"],
            "refresh_token": token["refresh_token"], "grant_type": "refresh_token",
        }).encode()
        request = urllib.request.Request(client.get("token_uri", "https://oauth2.googleapis.com/token"), data=body,
                                         headers={"content-type": "application/x-www-form-urlencoded", "user-agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=20) as response:
            data = json.loads(response.read())
        self.access_token = data["access_token"]
        self.token_expires = time.time() + float(data.get("expires_in", 3600)) - 60

    def _call(self, method: str, path: str, params: dict | None = None, body: dict | None = None) -> dict:
        if not self.access_token or time.time() > self.token_expires:
            self._refresh()
        url = f"{API}/{path}"
        if params:
            url += "?" + urllib.parse.urlencode(params)
        request = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None,
                                         headers={"authorization": f"Bearer {self.access_token}", "content-type": "application/json",
                                                  "user-agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                raw = response.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as error:
            try:
                detail = json.loads(error.read() or b"{}").get("error", {})
                message = detail.get("message") or str(detail)[:200]
            except ValueError:
                message = error.reason
            raise YouTubeError(error.code, str(message)[:300]) from None

    # MARK: - The stream (the channel's reusable key)

    def _find_stream(self) -> str:
        """The liveStream whose ingestion key is ours."""
        if self.stream_id:
            return self.stream_id
        data = self._call("GET", "liveStreams", {"part": "id,snippet,cdn,status", "mine": "true", "maxResults": 50})
        for item in data.get("items", []):
            info = item.get("cdn", {}).get("ingestionInfo", {})
            if info.get("streamName") == self.stream_key:
                self.stream_id = item["id"]
                return self.stream_id
        names = [item.get("snippet", {}).get("title") for item in data.get("items", [])]
        raise YouTubeError(404, f"no stream on the channel uses the relay's key (streams: {names})")

    def stream_status(self) -> tuple[str, str]:
        """(streamStatus: active/ready/inactive/error, healthStatus: good/ok/bad/noData)."""
        stream_id = self._find_stream()
        data = self._call("GET", "liveStreams", {"part": "status", "id": stream_id})
        status = (data.get("items") or [{}])[0].get("status", {})
        return status.get("streamStatus", "?"), status.get("healthStatus", {}).get("status", "?")

    # MARK: - The broadcast (one per session)

    def _load_session(self) -> None:
        try:
            saved = json.loads(SESSION_FILE.read_text(encoding="utf-8"))
            if isinstance(saved, dict) and time.time() - float(saved.get("created_at", 0)) < 6 * 3600:
                self.session_key, self.broadcast_id = saved.get("session_key"), saved.get("broadcast_id")
        except (OSError, ValueError):
            pass

    def _save_session(self) -> None:
        tmp = SESSION_FILE.with_suffix(".json.tmp")
        try:
            tmp.write_text(json.dumps({"session_key": self.session_key, "broadcast_id": self.broadcast_id, "created_at": time.time()}),
                           encoding="utf-8")
            os.replace(tmp, SESSION_FILE)
        except OSError as error:
            log(f"session file not saved: {error}")

    def _forget_session(self) -> None:
        self.session_key = self.broadcast_id = None
        SESSION_FILE.unlink(missing_ok=True)

    def ensure(self, session_key: str, title: str | None = None) -> str:
        """The broadcast for this platform session: the one made before (a
        relay restart) while it is still usable, else a new one bound to the
        stream, with auto-start and auto-stop. Returns its id."""
        if self.broadcast_id is None:
            self._load_session()
        if self.broadcast_id and self.session_key == session_key:
            life = self.lifecycle()
            if life in ("ready", "testing", "live", "liveStarting", "testStarting", "created"):
                return self.broadcast_id
            log(f"broadcast {self.broadcast_id} is {life}: making a new one")
            self._forget_session()
        stream_id = self._find_stream()
        adopted = self._adoptable(stream_id)
        if adopted:
            # Someone scheduled tonight's broadcast in Studio on our stream:
            # it is the session's broadcast, not a rival to one of ours.
            self.broadcast_id, self.session_key = adopted, session_key
            self._save_session()
            log(f"broadcast {adopted} (scheduled in Studio on the stream) adopted for this session")
            return adopted
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        created = self._call("POST", "liveBroadcasts", {"part": "snippet,status,contentDetails"}, {
            "snippet": {"title": (title or self.title)[:100], "description": self.description[:5000], "scheduledStartTime": now},
            "status": {"privacyStatus": self.privacy, "selfDeclaredMadeForKids": False},
            "contentDetails": {
                "enableAutoStart": True, "enableAutoStop": True, "enableDvr": True, "recordFromStart": True,
                "latencyPreference": "ultraLow", "monitorStream": {"enableMonitorStream": False},
            },
        })
        self.broadcast_id = created["id"]
        self.session_key = session_key
        self._call("POST", "liveBroadcasts/bind", {"id": self.broadcast_id, "part": "id,contentDetails", "streamId": stream_id})
        self._save_session()
        log(f"broadcast {self.broadcast_id} made and bound to the stream ({self.privacy}, auto-start)")
        return self.broadcast_id

    def _adoptable(self, stream_id: str) -> str | None:
        """A broadcast already on our stream that can carry this session: one
        that is live, else the 'ready' one scheduled soonest (a Studio-made
        event for tonight). None when there is none."""
        found: list[tuple[int, str, str]] = []
        for status in ("active", "upcoming"):
            # broadcastStatus already means "mine": the API refuses both together.
            data = self._call("GET", "liveBroadcasts", {"part": "id,snippet,status,contentDetails",
                                                         "broadcastStatus": status, "maxResults": 20})
            for item in data.get("items", []):
                details = item.get("contentDetails", {})
                life = item.get("status", {}).get("lifeCycleStatus", "")
                if details.get("boundStreamId") != stream_id or life not in ("live", "testing", "ready"):
                    continue
                # YouTube itself starts an auto-start broadcast when the stream
                # comes up, so among the ready ones that is the one to follow.
                rank = 0 if life == "live" else 1 if life == "testing" else 2 if details.get("enableAutoStart") else 3
                found.append((rank, item.get("snippet", {}).get("scheduledStartTime") or "9999", item["id"]))
        if not found:
            return None
        found.sort()
        return found[0][2]

    def lifecycle(self) -> str:
        """created, ready, testing, live, complete, revoked... or 'gone'."""
        if not self.broadcast_id:
            return "none"
        data = self._call("GET", "liveBroadcasts", {"part": "status", "id": self.broadcast_id})
        items = data.get("items") or []
        return items[0].get("status", {}).get("lifeCycleStatus", "?") if items else "gone"

    def go_live_if_ready(self) -> str:
        """Auto-start takes the broadcast live when the stream is active; this
        is the belt to its braces: with the stream active and the broadcast
        still 'ready', ask for the transition. Returns the lifecycle."""
        life = self.lifecycle()
        if life in ("ready", "testing"):
            stream, _ = self.stream_status()
            if stream == "active":
                life = self._transition("live") or life
                if life == "ready":
                    # A Studio-made broadcast keeps its monitor stream, which
                    # YouTube only lets go live from "testing": one step first.
                    life = self._transition("testing") or life
        return life

    def _transition(self, status: str) -> str | None:
        """Asks for a lifecycle transition; the new lifecycle, or None when
        YouTube refused it (logged, with its reason - a 403 here means the
        transition is not allowed yet, not a permission problem)."""
        try:
            self._call("POST", "liveBroadcasts/transition", {"id": self.broadcast_id, "broadcastStatus": status, "part": "status"})
            log(f"asked YouTube to take the broadcast to {status}")
            return self.lifecycle()
        except YouTubeError as error:
            log(f"transition to {status} refused: {error}")
            return None

    def complete(self) -> None:
        """The session is over: end the broadcast (if auto-stop has not) and forget it."""
        if not self.broadcast_id:
            return
        try:
            life = self.lifecycle()
            if life in ("live", "testing", "ready"):
                self._call("POST", "liveBroadcasts/transition",
                           {"id": self.broadcast_id, "broadcastStatus": "complete", "part": "status"})
                log(f"broadcast {self.broadcast_id} completed")
            else:
                log(f"broadcast {self.broadcast_id} already {life}")
        except YouTubeError as error:
            log(f"could not complete broadcast {self.broadcast_id}: {error}")
        self._forget_session()

    def watch_url(self) -> str:
        return f"https://www.youtube.com/watch?v={self.broadcast_id}" if self.broadcast_id else ""
