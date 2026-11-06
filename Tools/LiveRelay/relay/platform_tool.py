"""Hand controls for the platform's Our Sheikh Zikr, for when the relay got it
wrong during a session. Run on the relay server (it reads relay.env):

    python platform_tool.py status            what the apps and websites show now
    python platform_tool.py start             start (or find) the Zikr: Daily or Tahajjud by Pakistan time
    python platform_tool.py stage latifa-5    set the stage (tasbih, latifa-1..7, raabta, ahadiyat, maiyyat,
                                              aqrabiyyat, sair-kaaba, rauza-athar, masjid-nabawi, shajra)
    python platform_tool.py dua-card          show the Dua card (the session stays live)
    python platform_tool.py end               the dua: the platform ends the session 5 minutes later

Starting a new Zikr notifies every member again; "end" cannot be undone."""

from __future__ import annotations

import json
import sys
import time
import urllib.request

from cues import PlatformCues
from relay_agent import settings


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    cfg = settings()
    platform = cfg.get("PLATFORM_URL", "https://darul-irfan-platform.wajidmahmoodali1984-e23.workers.dev").rstrip("/")
    halqah = cfg.get("HALQAH_ID", "our-sheikh")
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    if command == "status":
        request = urllib.request.Request(f"{platform}/v1/public/live?ids={halqah}", headers={"user-agent": "DarulIrfanRelay/1.0"})
        with urllib.request.urlopen(request, timeout=10) as response:
            entry = next(iter(json.loads(response.read()).get("halqahs", [])), {})
        print(json.dumps({"live": entry.get("live"), "stage": entry.get("stage")}, ensure_ascii=False, indent=1))
        return 0
    token = cfg.get("PLATFORM_CUE_TOKEN", "")
    if not token:
        print("PLATFORM_CUE_TOKEN is not set in relay.env")
        return 2
    cues = PlatformCues(platform, halqah, token, test=cfg.get("PLATFORM_TEST") == "1")
    if command == "start":
        title = "Tahajjud Zikr" if (time.gmtime().tm_hour + 5) % 24 < 7 else "Daily Zikr"
        status, body = cues.start(title)
        print(f"start {title}: {status} {'(new session, members notified)' if status == 201 else '(already live)' if status == 200 else body}")
    elif command == "stage" and len(sys.argv) > 2:
        status, body = cues.post(sys.argv[2])
        print(f"stage {sys.argv[2]}: {status} {'ok' if status in (200, 201) else body}")
    elif command == "dua-card":
        status, body = cues.post("dua")
        print(f"dua card: {status} {'ok' if status in (200, 201) else body}")
    elif command == "end":
        status, body = cues.dua()
        print(f"dua (session ends 5 minutes later): {status}")
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
