# Restarts the relay (and its YouTube encoder). Safe during a session:
# the relay finds itself in the room and listeners pick the sound up again.
# Never kills Paltalk (a Paltalk restart may need a manual sign-in), and
# only the relay's own processes: the pythonw running relay_agent.py and
# the ffmpeg it started - never every pythonw or ffmpeg on the machine,
# which would take a picker replay or the owner's own encoder with them.
#   -DryRun   only say what would be stopped
#   -NoStart  stop the relay without starting the scheduled task again
param([switch]$DryRun, [switch]$NoStart)

$relays = @(Get-CimInstance Win32_Process -Filter "Name = 'pythonw.exe' OR Name = 'python.exe'" |
    Where-Object { $_.CommandLine -like '*relay_agent.py*' })
foreach ($relay in $relays) {
    # Its ffmpeg first, while the parent is still there to match it by.
    $encoders = @(Get-CimInstance Win32_Process -Filter "Name = 'ffmpeg.exe' AND ParentProcessId = $($relay.ProcessId)")
    foreach ($encoder in $encoders) {
        Write-Output "stopping ffmpeg $($encoder.ProcessId) (started by relay $($relay.ProcessId))"
        if (-not $DryRun) { Stop-Process -Id $encoder.ProcessId -Force -ErrorAction SilentlyContinue }
    }
    Write-Output "stopping relay $($relay.ProcessId): $($relay.CommandLine)"
    if (-not $DryRun) { Stop-Process -Id $relay.ProcessId -Force -ErrorAction SilentlyContinue }
}
if ($relays.Count -eq 0) { Write-Output "no relay process is running" }
if ($DryRun -or $NoStart) { return }
Start-Sleep 3
Start-ScheduledTask -TaskName "Darul Irfan Relay"
Start-Sleep 30
Get-Content C:\DarulIrfanRelay\relay.log -Tail 10
