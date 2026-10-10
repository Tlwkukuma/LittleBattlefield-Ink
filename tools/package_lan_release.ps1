param([string]$HostAddress = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts/proving_ground.gd') -Raw
$match = [regex]::Match($source, 'const\s+BUILD_VERSION\s*(?::\s*String)?\s*=\s*"([^"]+)"')
if (-not $match.Success) { throw 'Missing project BUILD_VERSION.' }
$version = $match.Groups[1].Value
if ($version -notmatch '^[A-Za-z0-9._-]+$') { throw 'BUILD_VERSION contains unsafe filename characters.' }
$HostAddress = $HostAddress.Trim()
if ($HostAddress) {
    if ($HostAddress -notmatch '^(\d{1,3}(?:\.\d{1,3}){3})(?::(\d{1,5}))?$') {
        throw 'HostAddress must be an IPv4 address with an optional port.'
    }
    $ipText = $Matches[1]
    $portText = $Matches[2]
    $address = $null
    if (-not [System.Net.IPAddress]::TryParse($ipText, [ref]$address) -or
        $address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'HostAddress must be an IPv4 address with an optional port.'
    }
    $HostAddress = $address.ToString()
    if ($portText) {
        $port = [int]$portText
        if ($port -lt 1 -or $port -gt 65535) { throw 'Host port must be between 1 and 65535.' }
        $HostAddress += ':' + $port
    }
}
$enginePath = 'G:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe'
if ($env:GODOT_EXE) { $enginePath = $env:GODOT_EXE }
if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) { throw 'Set GODOT_EXE to the installed Godot 4.6.3 console executable.' }
$engineVersion = (& $enginePath --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $engineVersion -notmatch '^4\.6\.3\.stable') { throw "Expected Godot 4.6.3 stable; found '$engineVersion'." }
# Never reuse a stage: an earlier host preset, stale DLL or failed export cannot leak in.
# Preserve previous releases and failed-build logs rather than deleting existing output.
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$packageName = "LittleBattlefield-LAN-v$version-Windows"
$buildDir = Join-Path $projectRoot "build/windows-v$version-$runId"
$releaseRoot = Join-Path $projectRoot "exports/$packageName-$runId/$packageName"
$zipPath = Join-Path $projectRoot "exports/$packageName-$runId.zip"
$null = New-Item -ItemType Directory -Path $buildDir
$gamePath = Join-Path $buildDir 'LittleBattlefield.exe'
$exportLog = Join-Path $buildDir 'export.log'
Write-Host "Exporting project v$version with Godot $engineVersion"
try {
    # Windows PowerShell turns native stderr warnings into error records.
    $ErrorActionPreference = 'Continue'
    & $enginePath --headless --path $projectRoot --export-release 'Windows Release' $gamePath *> $exportLog
    $exportExitCode = $LASTEXITCODE
} finally { $ErrorActionPreference = 'Stop' }
if ($exportExitCode -ne 0 -or (Select-String -LiteralPath $exportLog -Pattern '^\s*(SCRIPT ERROR|SHADER ERROR|ERROR):' -Quiet)) {
    throw "Release export failed: $exportLog"
}
foreach ($name in @('LittleBattlefield.exe', 'LittleBattlefield.pck')) {
    $file = Get-Item -LiteralPath (Join-Path $buildDir $name)
    if ($file.Length -eq 0) { throw "Empty export: $name" }
}
$null = New-Item -ItemType Directory -Path $releaseRoot
# Include Godot-generated companion files (e.g. console wrapper and native DLLs).
Get-ChildItem -LiteralPath $buildDir -File | Where-Object { $_.Name -ne 'export.log' } |
    Copy-Item -Destination $releaseRoot
Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'lan-release') -File |
    Copy-Item -Destination $releaseRoot
$releaseDocs = @{
    'docs/historical-five-levels.md' = '资料/historical-five-levels.md'
    'docs/pixi-fidelity-matrix.md' = '资料/pixi-fidelity-matrix.md'
    'docs/ten-level-source-runtime.md' = '资料/ten-level-source-runtime.md'
    'docs/combat-ai-iteration-20261009.md' = '资料/combat-ai-iteration-20261009.md'
}
foreach ($entry in $releaseDocs.GetEnumerator()) {
    $destination = Join-Path $releaseRoot $entry.Value
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot $entry.Key) -Destination $destination
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets/audio/free-firearms/LICENSE.md') -Destination (Join-Path $releaseRoot 'FREE_FIREARM_AUDIO_LICENSE.md')
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets/audio/free-firearms/ADDITIONAL_LICENSES.md') -Destination (Join-Path $releaseRoot 'ADDITIONAL_AUDIO_LICENSES.md')
Set-Content -LiteralPath (Join-Path $releaseRoot 'VERSION.txt') -Value $version -Encoding ASCII
Set-Content -LiteralPath (Join-Path $releaseRoot 'ENGINE_VERSION.txt') -Value $engineVersion -Encoding ASCII
if ($HostAddress) { Set-Content -LiteralPath (Join-Path $releaseRoot 'host-address.txt') -Value $HostAddress -Encoding ASCII }
# Hash every shipped file, including launchers and license notices; never hash this list itself.
$hashLines = @(Get-ChildItem -LiteralPath $releaseRoot -File -Recurse | Sort-Object FullName | ForEach-Object {
    $hash = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
    $relative = $_.FullName.Substring($releaseRoot.Length + 1).Replace('\', '/')
    '{0}  {1}' -f $hash.Hash.ToLowerInvariant(), $relative
})
# Launcher filenames include Chinese; ASCII destroys them. Use UTF-8 without BOM
# so the first digest also works with ordinary sha256sum-style readers.
[System.IO.File]::WriteAllLines((Join-Path $releaseRoot 'SHA256SUMS.txt'), [string[]]$hashLines, [System.Text.UTF8Encoding]::new($false))
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($releaseRoot, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $true)
$zipHash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
'{0}  {1}' -f $zipHash.Hash.ToLowerInvariant(), (Split-Path -Leaf $zipPath) |
    Set-Content -LiteralPath ($zipPath + '.sha256') -Encoding ASCII
Write-Host "Package: $zipPath"
Write-Host "Folder: $releaseRoot"
Write-Host "Host address preset: $HostAddress"
