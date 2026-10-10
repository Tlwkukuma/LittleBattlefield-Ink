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
$stdoutLog = Join-Path $projectRoot ('qa/performance/release-stdout-' + $runStamp + '.log')
$stderrLog = Join-Path $projectRoot ('qa/performance/release-stderr-' + $runStamp + '.log')
$pidFile = Join-Path $projectRoot ('qa/performance/release-pid-' + $runStamp + '.txt')
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
$gameArgs = @('--log-file', ('"' + $gameLog + '"'), '--', '--level01', '--briefing', $aiFlag, '--startup-watch')
if ($Range2) { $gameArgs = @('--log-file', ('"' + $gameLog + '"'), '--', '--range2', '--no-laya', '--startup-watch') }
# This is the requested interactive window. Keep other games/editors intact.
Get-Process | Where-Object { $_.MainWindowTitle -match '^v\d{4}\.\d{2}\.\d{2}\.\d+' } | ForEach-Object {
    Write-Host ('Existing PID {0}: {1}' -f $_.Id, $_.MainWindowTitle)
}
$helperArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $PSScriptRoot 'run_release_window.ps1') + '"'), '-GamePath', ('"' + $gamePath + '"'), '-ProjectRoot', ('"' + $projectRoot + '"'), '-GameLog', ('"' + $gameLog + '"'), '-StdoutLog', ('"' + $stdoutLog + '"'), '-StderrLog', ('"' + $stderrLog + '"'), '-PidFile', ('"' + $pidFile + '"'))
if ($Laya -and -not $Range2) { $helperArgs += '-Laya' }
if ($Range2) { $helperArgs += '-Range2' }
$loggerShell = (Get-Command powershell.exe -ErrorAction Stop).Source
$loggerProcess = Start-Process -FilePath $loggerShell -ArgumentList $helperArgs -WindowStyle Hidden -PassThru
$pidDeadline = (Get-Date).AddSeconds(10)
while (-not (Test-Path -LiteralPath $pidFile) -and (Get-Date) -lt $pidDeadline) {
    Start-Sleep -Milliseconds 100
    $loggerProcess.Refresh()
    if ($loggerProcess.HasExited) { throw 'Release output helper exited before starting the game.' }
}
if (-not (Test-Path -LiteralPath $pidFile)) { throw 'Release process ID was not recorded.' }
$gameProcess = Get-Process -Id ([int](Get-Content -LiteralPath $pidFile -Raw))
$deadline = (Get-Date).AddSeconds(30)
do {
    Start-Sleep -Milliseconds 250
    $gameProcess.Refresh()
    if ($gameProcess.HasExited) { throw ('Game exited during startup. See ' + $gameLog) }
} while (($gameProcess.MainWindowTitle -notlike ('*v' + $projectVersion + '*Release*')) -and (Get-Date) -lt $deadline)
# The first title belongs to the shared entry before Level 01 has finished
# loading. Verify both its ready marker and the delayed rendered-frame marker.
# Win32's Responding heuristic also reports false for the existing v58 game;
# it is diagnostic data, not sufficient evidence that Godot stopped updating.
$ready = $false
$framesReady = $false
while ((Get-Date) -lt $deadline) {
    foreach ($candidateLog in @($gameLog, $stdoutLog)) {
        if (-not (Test-Path -LiteralPath $candidateLog)) { continue }
        if (Select-String -LiteralPath $candidateLog -Pattern '^BUILD_VERSION_READY ' -Quiet) { $ready = $true }
        if (Select-String -LiteralPath $candidateLog -Pattern '^RANGE_READY scene=.* fps=[1-9]' -Quiet) { $framesReady = $true }
    }
    if ($ready -and $framesReady) { break }
    Start-Sleep -Milliseconds 250
    $gameProcess.Refresh()
    if ($gameProcess.HasExited) { throw ('Game exited during level loading. See ' + $gameLog) }
}
$gameProcess.Refresh()
if (-not $ready -or -not $framesReady -or $gameProcess.MainWindowTitle -notlike ('*v' + $projectVersion + '*Release*')) {
    throw ('Interactive startup was not verified for PID {0}. Inspect {1} and {2}; no ready launch identity was recorded.' -f $gameProcess.Id, $stdoutLog, $stderrLog)
}
$identity = [ordered]@{ version=$projectVersion; engine=$engineVersion; scene=$sceneIdentity; started=$gameProcess.StartTime.ToString('yyyy-MM-dd HH:mm:ss'); pid=$gameProcess.Id; title=$gameProcess.MainWindowTitle; renderedFramesVerified=$framesReady; windowsResponding=$gameProcess.Responding; log=$gameLog; stdout=$stdoutLog; stderr=$stderrLog; executable=$gamePath }
$identity | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $projectRoot 'qa/performance/latest-release-launch.json') -Encoding UTF8
if ($Range2) { $identity | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $projectRoot 'qa/performance/latest-range2-launch.json') -Encoding UTF8 }
Write-Host $gameProcess.MainWindowTitle
Write-Host ('Log: ' + $gameLog)
if ($gameProcess.MainWindowTitle -notlike ('*v' + $projectVersion + '*Release*')) { Write-Warning 'Startup title is not confirmed yet; check the game log.' }
