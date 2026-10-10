@echo off
setlocal
cd /d "%~dp0"
if /I "%~1"=="--laya" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_level_release.ps1" -Laya
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_level_release.ps1"
)
if errorlevel 1 pause
