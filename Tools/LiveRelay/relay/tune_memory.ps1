# Makes a 2 GB relay server survive memory spikes. Memory only: no security
# settings are touched. Run as Administrator; the page file needs a restart.
$ErrorActionPreference = 'Continue'

# A fixed 6 GB page file: a spike slows the relay instead of freezing the server.
$cs = Get-CimInstance Win32_ComputerSystem
if ($cs.AutomaticManagedPagefile) { Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false } }
$pf = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue
if ($pf) { Set-CimInstance -InputObject $pf -Property @{ InitialSize = [uint32]6144; MaximumSize = [uint32]6144 } }
else { New-CimInstance -ClassName Win32_PageFileSetting -Property @{ Name = 'C:\pagefile.sys'; InitialSize = [uint32]6144; MaximumSize = [uint32]6144 } | Out-Null }
'page file: ' + ((Get-CimInstance Win32_PageFileSetting | ForEach-Object { "$($_.Name) $($_.InitialSize)-$($_.MaximumSize) MB" }) -join ', ')

# Server Manager never opens at sign-in.
schtasks /Change /TN '\Microsoft\Windows\Server Manager\ServerManager' /Disable | Out-Null
if (-not (Test-Path 'HKLM:\SOFTWARE\Microsoft\ServerManager')) { New-Item -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' | Out-Null }
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name DoNotOpenServerManagerAtLogon -Value 1 -Type DWord
'Server Manager: off at sign-in'

# Indexing and prefetch services the relay does not need.
foreach ($name in 'WSearch', 'SysMain', 'MapsBroker') {
    $service = Get-Service $name -ErrorAction SilentlyContinue
    if ($service) { Stop-Service $name -Force -ErrorAction SilentlyContinue; Set-Service $name -StartupType Disabled; "disabled $name" }
}

# Edge does not keep itself running in the background.
New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Force | Out-Null
Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name StartupBoostEnabled -Value 0 -Type DWord
Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name BackgroundModeEnabled -Value 0 -Type DWord
'Edge: no background mode'
