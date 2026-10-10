@echo off
setlocal
cd /d "%~dp0"
set "SOLDIER_BLENDER=F:\apps\blender\blender.exe"
if defined BLENDER_EXE set "SOLDIER_BLENDER=%BLENDER_EXE%"
if not exist "%SOLDIER_BLENDER%" exit /b 1
start "" "%SOLDIER_BLENDER%" "%~dp0art\tripo-soldier\source-rig-equipped.blend"
