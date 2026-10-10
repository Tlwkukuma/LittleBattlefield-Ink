@echo off
setlocal
cd /d "%~dp0"
set "INK_GODOT=G:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe"
if defined GODOT_EXE set "INK_GODOT=%GODOT_EXE%"
if not exist "%INK_GODOT%" (
  echo Set GODOT_EXE to a Godot 4.6 executable, or import project.godot.
  pause
  exit /b 1
)
start "" "%INK_GODOT%" --path "%~dp0." res://proving_ground.tscn -- --equipment-wheel --startup-watch
