# Sets this PC up as a Daily Zikr listener: the agent starts when the listener
# account signs in to Windows and is restarted within a minute if it stops.
# It runs in the signed-in session because it reads Paltalk's window and the
# sound the PC plays. Run once, in that account, from this folder:
#
#   powershell -ExecutionPolicy Bypass -File install_listener.ps1
#
# Remove with: Unregister-ScheduledTask -TaskName 'Darul Irfan Listener'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$missing = @()
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { $missing += 'Python 3.12 (winget install Python.Python.3.12)' }
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue) -and
    -not (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Gyan.FFmpeg*\*\bin\ffmpeg.exe" -ErrorAction SilentlyContinue)) {
    $missing += 'ffmpeg (winget install Gyan.FFmpeg)'
}
if (-not (Test-Path "$env:LOCALAPPDATA\Paltalk\Paltalk.exe")) { $missing += 'Paltalk Desktop, signed in with the listener account' }
if (-not (Test-Path (Join-Path $here 'listener.env'))) { $missing += 'listener.env (see README)' }
if ($missing) {
    Write-Host "Install first:`n  - $($missing -join "`n  - ")"
    exit 1
}
python -m pip install --quiet --user pywinauto==0.6.9 PyAudioWPatch==0.2.12.7 psutil==6.1.1

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$here\run_listener.ps1`"" `
    -WorkingDirectory $here
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName 'Darul Irfan Listener' -Action $action -Trigger $trigger -Settings $settings `
    -Description 'Carries the Daily Zikr room to the live stream. Tools/LiveListener in the Darul Irfan repository.' -Force | Out-Null
Start-ScheduledTask -TaskName 'Darul Irfan Listener'
Write-Host "Installed and started. Log: $here\listener.log"
