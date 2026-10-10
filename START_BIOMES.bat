@echo off
setlocal
cd /d "%~dp0"
set "INK_BIOME_GODOT=G:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe"
if defined GODOT_EXE set "INK_BIOME_GODOT=%GODOT_EXE%"
start "" "%INK_BIOME_GODOT%" --path "%~dp0." res://proving_ground.tscn -- --biomes
