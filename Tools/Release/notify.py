"""Tell the owner on this PC: a Windows notification, and a line in
Darul Irfan/automation/UPDATES.md (outside git) that keeps every update.

The release automation runs from Task Scheduler with nobody watching, so each
outcome a person should know about (released, waiting on billing, stopped)
is announced this way.

    python Tools/Release/notify.py "<title>" "<message>"
"""
from __future__ import annotations

import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
UPDATES = ROOT / "automation" / "UPDATES.md"
# Windows PowerShell's own app id: toasts from an unregistered id are dropped.
APP_ID = r"{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
SCRIPT = r"""
$ErrorActionPreference = 'Stop'
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
$texts = $template.GetElementsByTagName('text')
$texts.Item(0).AppendChild($template.CreateTextNode($env:DI_TITLE)) | Out-Null
$texts.Item(1).AppendChild($template.CreateTextNode($env:DI_BODY)) | Out-Null
$toast = [Windows.UI.Notifications.ToastNotification]::new($template)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($env:DI_APP).Show($toast)
"""


def notify(title: str, body: str) -> None:
    UPDATES.parent.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    if not UPDATES.exists():
        UPDATES.write_text("# Darul Irfan: release updates\n\nNewest last.\n\n", encoding="utf-8")
    with UPDATES.open("a", encoding="utf-8") as handle:
        handle.write(f"- **{stamp} - {title}:** {body}\n")
    import os
    env = dict(os.environ, DI_TITLE=title, DI_BODY=body, DI_APP=APP_ID)
    try:
        subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", SCRIPT], env=env,
                       capture_output=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        pass   # the line in UPDATES.md is the record either way


if __name__ == "__main__":
    notify(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "")
