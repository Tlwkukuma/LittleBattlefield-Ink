param([switch]$Laya,[switch]$Range2)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts/proving_ground.gd') -Raw
$versionMatch = [regex]::Match($source, 'const BUILD_VERSION="([^"]+)"')
if (-not $versionMatch.Success) { throw 'Missing project BUILD_VERSION.' }
$projectVersion = $versionMatch.Groups[1].Value
$enginePath = 'G:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe'
if ($env:GODOT_EXE) { $enginePath = $env:GODOT_EXE }
if (-not (Test-Path -LiteralPath $enginePath)) { throw 'Set GODOT_EXE to the installed Godot 4.6 executable.' }
$engineVersion = (& $enginePath --version | Out-String).Trim()
$buildDir = Join-Path $projectRoot ('build/windows-v' + $projectVersion)
$null = New-Item -ItemType Directory -Path $buildDir -Force
$gamePath = Join-Path $buildDir 'LittleBattlefield.exe'
$runStamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$exportLog = Join-Path $projectRoot ('qa/performance/release-export-' + $runStamp + '.log')
$gameLog = Join-Path $projectRoot ('qa/performance-v' + $projectVersion + '-' + $runStamp + '.log')
$sceneIdentity = 'res://proving_ground.tscn / Level 01'
if ($Range2) { $sceneIdentity = 'res://proving_ground_2.tscn / Range 02' }
Write-Host ('Project v{0}; Godot {1}; scene {2}' -f $projectVersion, $engineVersion, $sceneIdentity)
# Rebuild current sources so another chat's resource/script edits cannot leave
# this entry silently running an older package with the same project version.
& $enginePath --headless --path $projectRoot --export-release 'Windows Release' $gamePath *> $exportLog
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $exportLog -Pattern '^(SCRIPT ERROR|SHADER ERROR|ERROR):' -Quiet)) {
    throw ('Release export failed. See ' + $exportLog)
}
if (-not (Test-Path -LiteralPath $gamePath)) { throw 'Release executable was not produced.' }
$aiFlag = '--no-laya'
if ($Laya) { & (Join-Path $PSScriptRoot 'start_laya.ps1'); $aiFlag = '--laya' }
$gameArgs = @('--log-file', ('"' + $gameLog + '"'), '--', '--level01', '--briefing', $aiFlag, '--startup-watch', '--performance-log')
if ($Range2) { $gameArgs = @('--log-file', ('"' + $gameLog + '"'), '--', '--range2', '--no-laya', '--startup-watch', '--performance-log') }
# This is the requested interactive window. Keep other games/editors intact.
Get-Process | Where-Object { $_.MainWindowTitle -match '^v\d{4}\.\d{2}\.\d{2}\.\d+' } | ForEach-Object {
    Write-Host ('Existing PID {0}: {1}' -f $_.Id, $_.MainWindowTitle)
}
$gameProcess = Start-Process -FilePath $gamePath -ArgumentList $gameArgs -WorkingDirectory $projectRoot -PassThru
$deadline = (Get-Date).AddSeconds(30)
do {
    Start-Sleep -Milliseconds 250
    $gameProcess.Refresh()
    if ($gameProcess.HasExited) { throw ('Game exited during startup. See ' + $gameLog) }
} while (($gameProcess.MainWindowTitle -notlike ('*v' + $projectVersion + '*Release*')) -and (Get-Date) -lt $deadline)
# The first title belongs to the shared entry before Level 01 has finished
# loading. Wait for its ready marker before recording the actual scene title.
while ((Get-Date) -lt $deadline) {
    if ((Test-Path -LiteralPath $gameLog) -and (Select-String -LiteralPath $gameLog -Pattern '^BUILD_VERSION_READY ' -Quiet)) { break }
    Start-Sleep -Milliseconds 250
    $gameProcess.Refresh()
    if ($gameProcess.HasExited) { throw ('Game exited during level loading. See ' + $gameLog) }
}
$gameProcess.Refresh()
$identity = [ordered]@{ version=$projectVersion; engine=$engineVersion; scene=$sceneIdentity; pid=$gameProcess.Id; title=$gameProcess.MainWindowTitle; log=$gameLog; executable=$gamePath }
$identity | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $projectRoot 'qa/performance/latest-release-launch.json') -Encoding UTF8
if ($Range2) { $identity | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $projectRoot 'qa/performance/latest-range2-launch.json') -Encoding UTF8 }
Write-Host $gameProcess.MainWindowTitle
Write-Host ('Log: ' + $gameLog)
if ($gameProcess.MainWindowTitle -notlike ('*v' + $projectVersion + '*Release*')) { Write-Warning 'Startup title is not confirmed yet; check the game log.' }
