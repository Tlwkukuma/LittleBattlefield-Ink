param([int]$WaitSeconds = 45)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$endpoint = 'http://127.0.0.1:8765'
if ($env:LAYA_AI_URL) { $endpoint = $env:LAYA_AI_URL.TrimEnd('/') }
if ($endpoint -notmatch '^http://(127\.0\.0\.1|localhost):([0-9]+)$') { throw 'Laya requires a local HTTP endpoint.' }
$listenPort = [int]$Matches[2]
function Get-LayaHealth {
    try {
        $result = Invoke-RestMethod -Uri "$endpoint/health" -TimeoutSec 2
        if ($result.ok -and $result.device -like 'cuda*') { return $result }
    } catch { }
    return $null
}
$health = Get-LayaHealth
if ($health) { Write-Output "LAYA_READY reused pid=$($health.pid) device=$($health.device) dtype=$($health.dtype)"; exit 0 }
# An occupied port may belong to a model that is still loading. Never launch a
# duplicate GPU model or terminate an unrelated owner of the endpoint.
$listener = Get-NetTCPConnection -LocalPort $listenPort -State Listen -ErrorAction SilentlyContinue
if (-not $listener) {
    $pythonPath = 'D:/Models/Pixi-Battlefield1-Blue/venv-laya/Scripts/python.exe'
    if ($env:LAYA_PYTHON) { $pythonPath = $env:LAYA_PYTHON }
    $modelPath = 'D:/Models/Laya/convaiinnovations-laya'
    if ($env:LAYA_MODEL) { $modelPath = $env:LAYA_MODEL }
    $adapterPath = [IO.Path]::GetFullPath((Join-Path $projectRoot '../../web/Pixi-Battlefield1-Blue/tools/laya_sidecar.py'))
    foreach ($required in @($pythonPath, $adapterPath, (Join-Path $modelPath 'model.safetensors'))) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Missing local Laya dependency: $required" }
    }
    $settings = @{
        LAYA_MODEL=$modelPath; LAYA_AI_PORT=[string]$listenPort; LAYA_AI_HOST='127.0.0.1'
        LAYA_DEVICE='cuda'; LAYA_REQUIRE_GPU='1'; LAYA_GPU_FP16='1'
        HF_HOME='D:/Models/huggingface'; TORCH_HOME='D:/Models/torch'
        HF_HUB_OFFLINE='1'; TRANSFORMERS_OFFLINE='1'; HF_HUB_DISABLE_XET='1'
        PYTHONUNBUFFERED='1'
    }
    $saved = @{}
    try {
        foreach ($key in $settings.Keys) { $saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process'); [Environment]::SetEnvironmentVariable($key,$settings[$key],'Process') }
        $logDirectory = Join-Path $projectRoot 'qa'
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $arguments = @('-u', ('"' + $adapterPath + '"'))
        $process = Start-Process -FilePath $pythonPath -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logDirectory "laya-$stamp.log") -RedirectStandardError (Join-Path $logDirectory "laya-$stamp-error.log")
        Write-Output "LAYA_START pid=$($process.Id) local_files_only=true"
    } finally {
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') }
    }
}
$deadline = (Get-Date).AddSeconds($WaitSeconds)
do {
    $health = Get-LayaHealth
    if ($health) { Write-Output "LAYA_READY pid=$($health.pid) device=$($health.device) dtype=$($health.dtype)"; exit 0 }
    if ($process -and $process.HasExited) { throw "Laya exited with code $($process.ExitCode); see qa/laya-*-error.log." }
    Start-Sleep -Milliseconds 500
} while ((Get-Date) -lt $deadline)
Write-Warning 'Laya is not ready. The battlefield will display and use its rule fallback.'
exit 1
