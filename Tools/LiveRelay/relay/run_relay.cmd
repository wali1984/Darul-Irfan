@echo off
rem Started by the "Darul Irfan Relay" task; output goes to relay.log.
rem UTF-8 output, so Urdu chat lines can be logged.
cd /d "%~dp0"
set PYTHONIOENCODING=utf-8
"C:\Program Files\Python312\python.exe" -u relay_agent.py >> relay.log 2>&1
