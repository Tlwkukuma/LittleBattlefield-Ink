#requires -version 5.1
param([switch]$Elevated, [switch]$SelfTest)
$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$gamePath = Join-Path $packageRoot 'LittleBattlefield.exe'
$ruleName = 'LittleBattlefield-LAN-Game-UDP'
$privateRanges = @('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '100.64.0.0/10')
if ($SelfTest) {
    if (-not (Test-Path -LiteralPath $gamePath)) { throw 'Missing LittleBattlefield.exe next to script.' }
    Write-Output "Program: $gamePath"
    Write-Output 'Inbound UDP: 27829, 27830; remote: private LAN ranges; profiles: Any'
    exit 0
}
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($Elevated) { throw 'Administrator permission was not granted.' }
    $escapedScript = $MyInvocation.MyCommand.Path.Replace('"', '')
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Elevated' -f $escapedScript
    $child = Start-Process -FilePath "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    exit $child.ExitCode
}
Add-Type -AssemblyName System.Windows.Forms
try {
    if (-not (Test-Path -LiteralPath $gamePath)) { throw '请将整个安装包解压，并保留 LittleBattlefield.exe 与此工具在同一文件夹。' }
    $old = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
    if ($old) { $old | Remove-NetFirewallRule }
    New-NetFirewallRule -Name $ruleName -DisplayName '小小战地 · 局域网游戏 UDP 27829 / 27830' -Direction Inbound -Action Allow -Protocol UDP -LocalPort 27829,27830 -RemoteAddress $privateRanges -Program $gamePath -Profile Any -Enabled True | Out-Null
    [void][System.Windows.Forms.MessageBox]::Show("已允许此文件夹中的小小战地接收局域网 UDP 27829 / 27830。`n`n请房主在游戏里开放战役，再让队友重新加入。`n搬到新文件夹后，请重新运行此工具。", '小小战地 · 局域网已允许')
} catch {
    [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '小小战地 · 放行未完成')
    exit 1
}
