# Starts the listener with its settings from listener.env (beside this script,
# never committed) and appends its output to listener.log, rotated at 5 MB.
# Run by the scheduled task that install_listener.ps1 registers.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $here 'listener.log'
if ((Test-Path $log) -and (Get-Item $log).Length -gt 5MB) { Move-Item $log "$log.1" -Force }

$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) {
    "$(Get-Date -Format s) python is not installed" | Out-File $log -Append -Encoding utf8
    exit 2
}
& $python -u (Join-Path $here 'listener_agent.py') *>> $log
exit $LASTEXITCODE
