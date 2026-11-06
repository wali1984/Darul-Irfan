# Run once, as Administrator, on a new relay server. Turns on Windows' own
# SSH server for the relay's maintainer: key sign-in only, no passwords.
#   powershell -ExecutionPolicy Bypass -File enable_ssh.ps1
$ErrorActionPreference = 'Stop'

Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
Set-Service sshd -StartupType Automatic
Start-Service sshd   # the first start writes sshd_config

# PowerShell, not cmd, for remote commands.
New-ItemProperty -Path HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -PropertyType String -Force `
    -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' | Out-Null

# The maintainer's public key. Windows reads administrators' keys from here,
# and only if no one but Administrators and SYSTEM can write the file.
$keys = 'C:\ProgramData\ssh\administrators_authorized_keys'
Set-Content $keys 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE4cp6G2YYjpgxSCMTjI92nlgCvOXYonBiBQAOBLSOcD claude-live-relay' -Encoding ascii
icacls $keys /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null

$config = 'C:\ProgramData\ssh\sshd_config'
(Get-Content $config) -replace '^#?PasswordAuthentication .*', 'PasswordAuthentication no' | Set-Content $config -Encoding ascii
Restart-Service sshd

$rule = Get-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue
if ($rule) { Set-NetFirewallRule -Name OpenSSH-Server-In-TCP -Enabled True -Profile Any }
else { New-NetFirewallRule -Name OpenSSH-Server-In-TCP -DisplayName 'OpenSSH Server (sshd)' -Protocol TCP -LocalPort 22 -Action Allow -Profile Any | Out-Null }

Write-Host 'SSH ready'
