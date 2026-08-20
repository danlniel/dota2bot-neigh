@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy-to-dota.ps1" %*
pause
