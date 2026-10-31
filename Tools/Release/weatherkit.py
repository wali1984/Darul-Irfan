"""Check Apple's WeatherKit access, then optionally configure Worker secrets.

The owner keeps Key ID, Issuer/Team ID, Service ID, and Path in a local note.
The .p8 is read from that Path, never printed or included in a mobile build.

  python Tools/Release/weatherkit.py --credentials <note> --service-id <registered-id>
  python Tools/Release/weatherkit.py --credentials <note> --configure
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import jwt

REPO = Path(__file__).resolve().parents[2]


def configuration(note: Path, service: str | None, team: str | None) -> dict[str, str]:
    text = note.read_text(encoding="utf-8")
    kid = re.search(r"Key\s*ID\s*:\s*([A-Z0-9]{10})", text, re.I)
    location = re.search(r"(?im)^\s*Path\s*:?\s*(.+)$", text)
    service_match = re.search(r"(?im)^\s*Service\s*ID\s*:\s*([\w.-]+)", text)
    team_match = re.search(r"(?im)^\s*(?:Issuer|Teams?|Issuer/Teams?)\s*ID\s*:\s*([A-Z0-9]{10})\s*$", text)
    if not kid or not location:
        raise ValueError("The credentials note needs Key ID and Path fields")
    service = service or (service_match.group(1) if service_match else None)
    if not service or not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", service):
        raise ValueError("Add the registered WeatherKit Service ID to the note; it is separate from the Key ID and Team ID")
    if not team:
        team = team_match.group(1) if team_match else None
    if not team:
        match = re.search(r'DEVELOPMENT_TEAM:\s*"([A-Z0-9]{10})"', (REPO / "project.yml").read_text(encoding="utf-8"))
        team = match.group(1) if match else None
    if not team or not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("WeatherKit needs the 10-character Apple Team ID, not an App Store Connect issuer UUID")
    key = Path(location.group(1).strip(' `"'))
    if key.is_dir():
        key = key / f"AuthKey_{kid.group(1)}.p8"
    if not key.is_file():
        raise ValueError("The WeatherKit private key was not found at the note's Path")
    return {"WEATHERKIT_TEAM_ID": team, "WEATHERKIT_KEY_ID": kid.group(1), "WEATHERKIT_SERVICE_ID": service, "WEATHERKIT_PRIVATE_KEY": key.read_text(encoding="utf-8")}


def probe(config: dict[str, str]) -> bool:
    now = int(time.time())
    team, service, kid = (config[k] for k in ["WEATHERKIT_TEAM_ID", "WEATHERKIT_SERVICE_ID", "WEATHERKIT_KEY_ID"])
    bearer = jwt.encode({"iss": team, "iat": now, "exp": now + 900, "sub": service}, config["WEATHERKIT_PRIVATE_KEY"], algorithm="ES256", headers={"kid": kid, "id": f"{team}.{service}"})
    request = urllib.request.Request("https://weatherkit.apple.com/api/v1/weather/en-US/31.5/74.4?dataSets=currentWeather", headers={"Authorization": "Bearer " + bearer})
    try:
        with urllib.request.urlopen(request, timeout=25) as response:
            body = json.load(response)
        if not isinstance(body.get("currentWeather", {}).get("temperature"), (int, float)):
            print("Apple answered without a current weather reading")
            return False
        print("Apple WeatherKit access verified: current weather returned")
        return True
    except urllib.error.HTTPError as error:
        try:
            reason = json.loads(error.read()).get("reason", "unavailable")
        except (ValueError, AttributeError):
            reason = "unavailable"
        print(f"Apple WeatherKit: HTTP {error.code}, {reason}")
        return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--credentials", type=Path, default=REPO.parent / "DarulIrfan-iOS/Docs/Apple WeatherKit.md")
    parser.add_argument("--service-id")
    parser.add_argument("--team-id")
    parser.add_argument("--configure", action="store_true")
    args = parser.parse_args()
    try:
        config = configuration(args.credentials, args.service_id, args.team_id)
        if not probe(config):
            return 1
        if args.configure:
            command = ["cmd", "/d", "/c", "npx", "wrangler", "secret", "bulk"] if sys.platform == "win32" else ["npx", "wrangler", "secret", "bulk"]
            result = subprocess.run(command, input=json.dumps(config), cwd=REPO / "Server", text=True, capture_output=True, timeout=120)
            if result.returncode:
                print("Cloudflare secret configuration failed; check Wrangler account access. No credential values were logged.")
                return 1
            print("Configured the four WeatherKit Worker secrets; no signing key is stored in app source")
        return 0
    except (OSError, ValueError, urllib.error.URLError, subprocess.TimeoutExpired) as error:
        print(str(error) if isinstance(error, ValueError) else f"WeatherKit setup could not complete ({type(error).__name__})")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
