# Run once, as Administrator, on a new relay server. Turns on Windows' own
# SSH server for the relay's maintainer: key sign-in only, no passwords.
#   powershell -ExecutionPolicy Bypass -File enable_ssh.ps1
# Safe to run again. Wrapped in one block so it also works pasted into a
# console (9 November, Contabo: a pasted copy stopped after the install step).
& {
$ErrorActionPreference = 'Stop'

# Windows Server 2025 already has the SSH server (stopped, manual): installing
# it again can fail, and on Contabo it stopped the script there.
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
}
Set-Service sshd -StartupType Automatic
Start-Service sshd   # the first start writes sshd_config and the host keys

# PowerShell, not cmd, for remote commands.
New-Item -Path HKLM:\SOFTWARE\OpenSSH -Force | Out-Null
New-ItemProperty -Path HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -PropertyType String -Force `
    -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' | Out-Null

# The maintainer's public key. Windows reads administrators' keys from here,
# and only if no one but Administrators and SYSTEM can write the file
# (granted by SID, so it works whatever the system's language).
New-Item -ItemType Directory -Path C:\ProgramData\ssh -Force | Out-Null
$keys = 'C:\ProgramData\ssh\administrators_authorized_keys'
Set-Content $keys 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE4cp6G2YYjpgxSCMTjI92nlgCvOXYonBiBQAOBLSOcD claude-live-relay' -Encoding ascii
icacls $keys /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' | Out-Null

$config = 'C:\ProgramData\ssh\sshd_config'
(Get-Content $config) -replace '^#?PasswordAuthentication .*', 'PasswordAuthentication no' | Set-Content $config -Encoding ascii
Restart-Service sshd

# Every network profile: a VPS's network is "Public", and Windows' own rule
# allows only "Private" (Contabo, 9 November).
$rule = Get-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue
if ($rule) { Set-NetFirewallRule -Name OpenSSH-Server-In-TCP -Enabled True -Profile Any }
else { New-NetFirewallRule -Name OpenSSH-Server-In-TCP -DisplayName 'OpenSSH Server (sshd)' -Protocol TCP -LocalPort 22 -Action Allow -Profile Any | Out-Null }

Get-Service sshd | Format-Table Name, Status, StartType
Write-Host 'SSH ready'
}
