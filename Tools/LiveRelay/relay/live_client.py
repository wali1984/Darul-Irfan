"""The staging Worker's API and one-track WebRTC publish / pull through the
Realtime SFU it proxies. Used by the relay agent and by the test scripts."""

from __future__ import annotations

import asyncio
import json
import urllib.error
import urllib.request

from aiortc import RTCConfiguration, RTCIceServer, RTCPeerConnection, RTCSessionDescription

# Cloudflare refuses Python's default "Python-urllib" signature (error 1010).
USER_AGENT = "DarulIrfanRelay/1.0"


class ApiError(Exception):
    def __init__(self, status: int, data: dict) -> None:
        super().__init__(data.get("error") or data.get("errorDescription") or f"HTTP {status}")
        self.status, self.data = status, data


class Worker:
    def __init__(self, base_url: str, key: str) -> None:
        self.base, self.key = base_url.rstrip("/"), key

    def _call(self, method: str, path: str, body: dict | None = None, headers: dict | None = None) -> dict:
        # headers: extra request headers, such as the SFU session token.
        request = urllib.request.Request(
            self.base + path, method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={"content-type": "application/json", "x-live-key": self.key, "user-agent": USER_AGENT, **(headers or {})})
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                data = json.loads(response.read() or b"{}")
        except urllib.error.HTTPError as error:
            try:
                data = json.loads(error.read() or b"{}")
            except ValueError:
                data = {}
            raise ApiError(error.code, data) from None
        if data.get("errorCode"):
            raise ApiError(200, data)
        return data

    async def call(self, method: str, path: str, body: dict | None = None, headers: dict | None = None) -> dict:
        return await asyncio.to_thread(self._call, method, path, body, headers)

    async def open_session(self) -> tuple[str, dict]:
        """Opens an SFU session; returns its id and the headers every later
        call on it must carry (the Worker's session token, which ties the
        session to this key and role)."""
        session = await self.call("POST", "/api/sfu/sessions/new")
        token = session.get("sessionToken")
        return session["sessionId"], ({"x-live-session": token} if token else {})


def _peer() -> RTCPeerConnection:
    return RTCPeerConnection(RTCConfiguration(iceServers=[RTCIceServer(urls="stun:stun.cloudflare.com:3478")]))


async def publish(worker: Worker, track, track_name: str) -> tuple[RTCPeerConnection, str]:
    """Sends one local audio track to the SFU; returns the connection and its SFU session id."""
    pc = _peer()
    transceiver = pc.addTransceiver(track, direction="sendonly")
    await pc.setLocalDescription(await pc.createOffer())
    session_id, headers = await worker.open_session()
    result = await worker.call("POST", f"/api/sfu/sessions/{session_id}/tracks/new", {
        "sessionDescription": {"type": "offer", "sdp": pc.localDescription.sdp},
        "tracks": [{"location": "local", "mid": transceiver.mid, "trackName": track_name}],
    }, headers)
    await pc.setRemoteDescription(RTCSessionDescription(**result["sessionDescription"]))
    return pc, session_id


async def pull(worker: Worker, remote_session: str, track_name: str, timeout: float = 15):
    """Receives one remote audio track; returns (connection, track)."""
    pc = _peer()
    arrived: asyncio.Future = asyncio.get_running_loop().create_future()

    @pc.on("track")
    def _on_track(track) -> None:
        if not arrived.done():
            arrived.set_result(track)

    session_id, headers = await worker.open_session()
    result = await worker.call("POST", f"/api/sfu/sessions/{session_id}/tracks/new", {
        "tracks": [{"location": "remote", "sessionId": remote_session, "trackName": track_name}],
    }, headers)
    track_info = (result.get("tracks") or [{}])[0]
    if track_info.get("errorCode"):
        await pc.close()
        raise ApiError(200, track_info)
    await pc.setRemoteDescription(RTCSessionDescription(**result["sessionDescription"]))
    await pc.setLocalDescription(await pc.createAnswer())
    await worker.call("PUT", f"/api/sfu/sessions/{session_id}/renegotiate", {
        "sessionDescription": {"type": "answer", "sdp": pc.localDescription.sdp},
    }, headers)
    try:
        track = await asyncio.wait_for(arrived, timeout)
    except asyncio.TimeoutError:
        await pc.close()
        raise
    return pc, track
