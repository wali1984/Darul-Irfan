# Prepares a Windows (Server) machine as the live relay. Run as Administrator
# from this folder. Safe to run again: each step checks before it acts.
#   powershell -ExecutionPolicy Bypass -File install_relay.ps1
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$downloads = Join-Path $env:ProgramData 'DarulIrfanRelay\downloads'
New-Item -ItemType Directory -Force $downloads | Out-Null

function Step($text) { Write-Host "== $text" }

# 1. Windows Audio: off by default on Windows Server.
Step 'Windows Audio service'
foreach ($name in 'AudioEndpointBuilder', 'Audiosrv') {
    Set-Service $name -StartupType Automatic
    Start-Service $name
}

# 2. Python 3.12 for all users.
$python = 'C:\Program Files\Python312\python.exe'
if (-not (Test-Path $python)) {
    Step 'Python 3.12'
    $installer = Join-Path $downloads 'python-3.12.10-amd64.exe'
    Invoke-WebRequest 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe' -OutFile $installer -UseBasicParsing
    Start-Process $installer -ArgumentList '/quiet', 'InstallAllUsers=1', 'PrependPath=1', 'Include_test=0' -Wait
}

# 3. ffmpeg (for the YouTube programme).
$ffmpegDir = 'C:\ffmpeg'
if (-not (Test-Path "$ffmpegDir\bin\ffmpeg.exe")) {
    Step 'ffmpeg'
    $zip = Join-Path $downloads 'ffmpeg.zip'
    Invoke-WebRequest 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' -OutFile $zip -UseBasicParsing
    $tmp = Join-Path $downloads 'ffmpeg'
    Expand-Archive $zip $tmp -Force
    $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
    New-Item -ItemType Directory -Force $ffmpegDir | Out-Null
    Copy-Item "$($inner.FullName)\*" $ffmpegDir -Recurse -Force
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($machinePath -notlike "*$ffmpegDir\bin*") {
        [Environment]::SetEnvironmentVariable('Path', "$machinePath;$ffmpegDir\bin", 'Machine')
    }
}

# 4. VB-CABLE: the virtual cable Paltalk's speaker plays into, so only the
#    room's sound is captured. Donationware (vb-audio.com) - see README.
$haveCable = Get-CimInstance Win32_SoundDevice | Where-Object { $_.Name -like '*VB-Audio*' }
if (-not $haveCable) {
    Step 'VB-CABLE driver'
    $zip = Join-Path $downloads 'vbcable.zip'
    foreach ($pack in 'VBCABLE_Driver_Pack45.zip', 'VBCABLE_Driver_Pack43.zip') {
        try { Invoke-WebRequest "https://download.vb-audio.com/Download_CABLE/$pack" -OutFile $zip -UseBasicParsing; break } catch { }
    }
    $dir = Join-Path $downloads 'vbcable'
    Expand-Archive $zip $dir -Force
    $setup = Join-Path $dir 'VBCABLE_Setup_x64.exe'
    # Trust the publisher first, or Windows asks on screen and the silent install stalls.
    $cert = (Get-AuthenticodeSignature (Get-ChildItem $dir -Filter '*.cat' | Select-Object -First 1).FullName).SignerCertificate
    if (-not $cert) { $cert = (Get-AuthenticodeSignature $setup).SignerCertificate }
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('TrustedPublisher', 'LocalMachine')
    $store.Open('ReadWrite'); $store.Add($cert); $store.Close()
    Start-Process $setup -ArgumentList '-i', '-h' -Wait
    Start-Sleep 5
}

# 4b. Hi-Fi Cable: the second cable, Paltalk's microphone. The relay plays
#     the app's broadcast into "Hi-Fi Cable Input"; Paltalk records its other
#     end. Used only when the relay may speak (LISTEN_ONLY=0).
$haveHiFi = Get-CimInstance Win32_SoundDevice | Where-Object { $_.Name -like '*Hi-Fi Cable*' }
if (-not $haveHiFi) {
    Step 'Hi-Fi Cable driver'
    $zip = Join-Path $downloads 'hificable.zip'
    Invoke-WebRequest 'https://download.vb-audio.com/Download_CABLE/HiFiCableAsioBridgeSetup_v1007.zip' -OutFile $zip -UseBasicParsing
    $dir = Join-Path $downloads 'hificable'
    Expand-Archive $zip $dir -Force
    $setup = Get-ChildItem $dir -Recurse -Filter '*Setup*x64*.exe' | Select-Object -First 1
    if (-not $setup) { $setup = Get-ChildItem $dir -Recurse -Filter '*Setup*.exe' | Select-Object -First 1 }
    $cat = Get-ChildItem $dir -Recurse -Filter '*.cat' | Select-Object -First 1
    $cert = if ($cat) { (Get-AuthenticodeSignature $cat.FullName).SignerCertificate } else { (Get-AuthenticodeSignature $setup.FullName).SignerCertificate }
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('TrustedPublisher', 'LocalMachine')
    $store.Open('ReadWrite'); $store.Add($cert); $store.Close()
    Start-Process $setup.FullName -ArgumentList '-i', '-h' -Wait
    Start-Sleep 5
}

# 5. Python packages.
Step 'Python packages'
& $python -m pip install --quiet --upgrade pip
& $python -m pip install --quiet aiortc sounddevice numpy pywinauto psutil

# 6. Paltalk's speaker -> the cable: make the cable the default playback
#    device (Paltalk follows the default unless set otherwise).
Step 'Default playback device -> CABLE Input'
if (-not (Get-Module -ListAvailable AudioDeviceCmdlets)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
    Set-PSRepository PSGallery -InstallationPolicy Trusted
    Install-Module AudioDeviceCmdlets -Scope AllUsers -Force
}
Import-Module AudioDeviceCmdlets
$cable = Get-AudioDevice -List | Where-Object { $_.Type -eq 'Playback' -and $_.Name -like 'CABLE Input*' } | Select-Object -First 1
if ($cable) { Set-AudioDevice -ID $cable.ID | Out-Null; Write-Host "default playback: $($cable.Name)" } else { Write-Warning 'CABLE Input not found' }
# Paltalk's mic follows the default recording device: the Hi-Fi cable, never
# CABLE Output (that is the room itself, and would echo it back).
$mic = Get-AudioDevice -List | Where-Object { $_.Type -eq 'Recording' -and $_.Name -like 'Hi-Fi Cable Output*' } | Select-Object -First 1
if ($mic) { Set-AudioDevice -ID $mic.ID | Out-Null; Write-Host "default recording: $($mic.Name)" } else { Write-Warning 'Hi-Fi Cable Output not found' }

# Windows' microphone privacy switch: while it says Deny, recording the
# cable returns only silence.
Step 'Microphone access for desktop apps'
$consent = 'Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone'
foreach ($key in "HKLM:\$consent", "HKCU:\$consent", "HKCU:\$consent\NonPackaged") {
    New-Item -Path $key -Force | Out-Null
    Set-ItemProperty $key -Name Value -Value 'Allow'
}

# 7. Never sleep; the relay must be up whenever the room opens.
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0

# 8. Start in the signed-in desktop session (Paltalk is a desktop app), at
#    every sign-in, restarting if it stops.
Step 'Scheduled task "Darul Irfan Relay"'
# pythonw: no console window over Paltalk; the agent writes relay.log itself.
$action = New-ScheduledTaskAction -Execute 'C:\Program Files\Python312\pythonw.exe' -Argument "-u `"$here\relay_agent.py`"" -WorkingDirectory $here
# A workgroup server has no domain: the account is MACHINE\user, as whoami says.
$me = (whoami)
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $me
$settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Highest
Register-ScheduledTask 'Darul Irfan Relay' -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Write-Host 'done'
