param(
    [Parameter(Mandatory=$true)][string]$GamePath,
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$GameLog,
    [Parameter(Mandatory=$true)][string]$StdoutLog,
    [Parameter(Mandatory=$true)][string]$StderrLog,
    [Parameter(Mandatory=$true)][string]$PidFile,
    [switch]$Laya,
    [switch]$Range2
)
$ErrorActionPreference = 'Stop'
$AIFlag = '--no-laya'
if ($Laya) { $AIFlag = '--laya' }
$arguments = @('--log-file', ('"' + $GameLog + '"'), '--', '--level01', '--briefing', $AIFlag, '--startup-watch')
if ($Range2) { $arguments = @('--log-file', ('"' + $GameLog + '"'), '--', '--range2', '--no-laya', '--startup-watch') }
# Own the output pumps for the entire game lifetime. The Codex command shell
# may exit after startup; it must not orphan the child's redirected pipe readers.
$game = Start-Process -FilePath $GamePath -ArgumentList $arguments -WorkingDirectory $ProjectRoot -RedirectStandardOutput $StdoutLog -RedirectStandardError $StderrLog -PassThru
$game.Id | Set-Content -LiteralPath $PidFile -Encoding ASCII
$game.WaitForExit()
