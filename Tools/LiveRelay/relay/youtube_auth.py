"""One-time Google consent for the relay's YouTube broadcasts.

    python youtube_auth.py [path/to/youtube-oauth-client.json] [path/to/youtube-token.json]

Opens Google's consent page in the browser (the channel's account must
approve), receives the code on a loopback port, exchanges it for a refresh
token and writes youtube-token.json. Nothing is printed but the URL. The
token file then goes beside the relay (never in git). Standard library only.

    python youtube_auth.py --check [client] [token]    tries the token and lists the channel's streams
"""

from __future__ import annotations

import http.server
import json
import secrets
import sys
import threading
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path

SCOPE = "https://www.googleapis.com/auth/youtube"


def consent(client_path: Path, token_path: Path) -> int:
    data = json.loads(client_path.read_text(encoding="utf-8"))
    client = data.get("installed") or data.get("web")
    if not client:
        print("the client file is not a Desktop-app OAuth client")
        return 2
    state = secrets.token_urlsafe(16)
    got: dict = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802 - http.server's name
            query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if query.get("state", [""])[0] == state and "code" in query:
                got["code"] = query["code"][0]
                body = b"<h2>Darul Irfan relay: consent received. You can close this tab.</h2>"
            else:
                body = b"<h2>That did not carry a code; try again from the terminal.</h2>"
            self.send_response(200)
            self.send_header("content-type", "text/html")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args) -> None:  # noqa: ANN002 - quiet
            pass

    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    redirect = f"http://127.0.0.1:{port}/"
    url = client.get("auth_uri", "https://accounts.google.com/o/oauth2/auth") + "?" + urllib.parse.urlencode({
        "client_id": client["client_id"], "redirect_uri": redirect, "response_type": "code", "scope": SCOPE,
        "access_type": "offline", "prompt": "consent", "state": state,
    })
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print("Approve the relay in the browser (the YouTube channel's Google account):")
    print(url)
    webbrowser.open(url)
    while "code" not in got:
        threading.Event().wait(0.5)
    server.shutdown()
    body = urllib.parse.urlencode({
        "code": got["code"], "client_id": client["client_id"], "client_secret": client["client_secret"],
        "redirect_uri": redirect, "grant_type": "authorization_code",
    }).encode()
    request = urllib.request.Request(client.get("token_uri", "https://oauth2.googleapis.com/token"), data=body,
                                     headers={"content-type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(request, timeout=30) as response:
        token = json.loads(response.read())
    if "refresh_token" not in token:
        print("Google answered without a refresh token (was consent already given? remove the app at myaccount.google.com/permissions and run again)")
        return 1
    token_path.write_text(json.dumps({"refresh_token": token["refresh_token"], "scope": token.get("scope", SCOPE)}), encoding="utf-8")
    print(f"token saved to {token_path}")
    return 0


def check(client_path: Path, token_path: Path) -> int:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import youtube_live
    youtube_live.CLIENT_FILE, youtube_live.TOKEN_FILE = client_path, token_path
    yt = youtube_live.YouTube(stream_key="", title="check")
    data = yt._call("GET", "liveStreams", {"part": "id,snippet,status", "mine": "true", "maxResults": 50})  # noqa: SLF001
    for item in data.get("items", []):
        print(f"stream {item['id']}: {item['snippet'].get('title')!r} status={item.get('status', {}).get('streamStatus')}")
    data = yt._call("GET", "liveBroadcasts", {"part": "id,snippet,status", "mine": "true", "maxResults": 10})  # noqa: SLF001
    for item in data.get("items", []):
        print(f"broadcast {item['id']}: {item['snippet'].get('title')!r} {item['status'].get('lifeCycleStatus')} "
              f"{item['snippet'].get('scheduledStartTime')}")
    print("token works")
    return 0


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    here = Path(__file__).resolve().parent
    client_path = Path(args[0]) if args else here / "youtube-oauth-client.json"
    token_path = Path(args[1]) if len(args) > 1 else here / "youtube-token.json"
    if "--check" in sys.argv:
        return check(client_path, token_path)
    return consent(client_path, token_path)


if __name__ == "__main__":
    sys.exit(main())
