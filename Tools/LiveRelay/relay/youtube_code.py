"""Finishes a Google consent whose loopback listener was gone: takes the
redirect URL the browser showed (http://127.0.0.1:PORT/?state=...&code=...)
and exchanges its code for the refresh token.

    python youtube_code.py "<redirect url>" [client.json] [token.json]

The code is single-use and bound to the port in the URL; nothing is printed
but the result."""

from __future__ import annotations

import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path


def main() -> int:
    url = sys.argv[1]
    here = Path(__file__).resolve().parent
    client_path = Path(sys.argv[2]) if len(sys.argv) > 2 else here / "youtube-oauth-client.json"
    token_path = Path(sys.argv[3]) if len(sys.argv) > 3 else here / "youtube-token.json"
    parts = urllib.parse.urlparse(url.strip())
    query = urllib.parse.parse_qs(parts.query)
    code = query.get("code", [""])[0]
    if not code:
        print("that URL carries no code")
        return 2
    redirect = f"{parts.scheme}://{parts.netloc}/"
    data = json.loads(client_path.read_text(encoding="utf-8"))
    client = data.get("installed") or data.get("web")
    body = urllib.parse.urlencode({
        "code": code, "client_id": client["client_id"], "client_secret": client["client_secret"],
        "redirect_uri": redirect, "grant_type": "authorization_code",
    }).encode()
    request = urllib.request.Request(client.get("token_uri", "https://oauth2.googleapis.com/token"), data=body,
                                     headers={"content-type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            token = json.loads(response.read())
    except urllib.error.HTTPError as error:
        detail = json.loads(error.read() or b"{}")
        print("Google refused the code:", detail.get("error"), detail.get("error_description"))
        return 1
    if "refresh_token" not in token:
        print("Google answered without a refresh token")
        return 1
    token_path.write_text(json.dumps({"refresh_token": token["refresh_token"], "scope": token.get("scope", "")}), encoding="utf-8")
    print(f"token saved to {token_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
