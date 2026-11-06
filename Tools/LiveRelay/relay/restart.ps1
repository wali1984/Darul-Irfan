# Restarts the relay (and its YouTube encoder). Safe during a session:
# the relay finds itself in the room and listeners pick the sound up again.
# Never kills Paltalk (a Paltalk restart may need a manual sign-in).
Get-Process pythonw,ffmpeg -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 3
Start-ScheduledTask -TaskName "Darul Irfan Relay"
Start-Sleep 30
Get-Content C:\DarulIrfanRelay\relay.log -Tail 10
