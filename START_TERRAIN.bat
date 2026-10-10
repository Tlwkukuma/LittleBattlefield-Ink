@echo off
setlocal
cd /d "%~dp0"
set "INK_TERRAIN_GODOT=G:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe"
if defined GODOT_EXE set "INK_TERRAIN_GODOT=%GODOT_EXE%"
start "" "%INK_TERRAIN_GODOT%" --path "%~dp0." res://proving_ground.tscn -- --terrain
