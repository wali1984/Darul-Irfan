# Keeps the relay's desktop session alive with nobody connected. Run as
# Administrator:
#   powershell -ExecutionPolicy Bypass -File keep_signed_in.ps1
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$dir = Join-Path $env:ProgramData 'DarulIrfanRelay'
New-Item -ItemType Directory -Force $dir | Out-Null

# 1. Sign in by itself after every restart: Sysinternals Autologon, which
#    keeps the password as an encrypted LSA secret. The password is typed
#    into its window by an administrator on the server, never sent here.
$autologon = Join-Path $dir 'Autologon64.exe'
if (-not (Test-Path $autologon)) {
    Invoke-WebRequest 'https://live.sysinternals.com/Autologon64.exe' -OutFile $autologon -UseBasicParsing
}
Write-Host "autologon tool ready: $autologon (run it on the server and press Enable)"

# 2. Closing Remote Desktop leaves the session "disconnected", where Paltalk
#    stops drawing and UI automation fails. Move it to the console instead:
#    a SYSTEM task on every disconnect (event 24) hands the session to the
#    console, where it keeps running unlocked with nobody connected.
$toConsole = Join-Path $dir 'to_console.ps1'
@'
Start-Sleep -Seconds 2
foreach ($line in (quser 2>$null)) {
    if ($line -match '^\s*>?(\S+)\s+(\d+)\s+Disc') { tscon $Matches[2] /dest:console }
}
'@ | Set-Content -Path $toConsole -Encoding ascii
$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="Microsoft-Windows-TerminalServices-LocalSessionManager/Operational"&gt;&lt;Select Path="Microsoft-Windows-TerminalServices-LocalSessionManager/Operational"&gt;*[System[(EventID=24)]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
  </Triggers>
  <Principals><Principal id="Author"><UserId>S-1-5-18</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec><Command>powershell.exe</Command><Arguments>-NoProfile -ExecutionPolicy Bypass -File "$toConsole"</Arguments></Exec>
  </Actions>
</Task>
"@
Register-ScheduledTask -TaskName 'Darul Irfan Relay - keep session on console' -Xml $xml -Force | Out-Null
Write-Host 'disconnect -> console task registered'

# 3. No idle or disconnect limits, no screen saver or lock.
$ts = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
New-Item -Path $ts -Force | Out-Null
foreach ($name in 'MaxIdleTime', 'MaxDisconnectionTime') { Set-ItemProperty $ts -Name $name -Value 0 -Type DWord }
Set-ItemProperty $ts -Name 'fResetBroken' -Value 0 -Type DWord
$desktop = 'HKCU:\Control Panel\Desktop'
Set-ItemProperty $desktop -Name 'ScreenSaveActive' -Value '0'
Set-ItemProperty $desktop -Name 'ScreenSaverIsSecure' -Value '0'
$personal = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
New-Item -Path $personal -Force | Out-Null
Set-ItemProperty $personal -Name 'NoLockScreen' -Value 1 -Type DWord
powercfg /change monitor-timeout-ac 0
powercfg /change standby-timeout-ac 0
Write-Host 'no idle limits, no lock'
