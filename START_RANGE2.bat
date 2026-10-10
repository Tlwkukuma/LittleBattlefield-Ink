@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_level_release.ps1" -Range2
if errorlevel 1 pause
