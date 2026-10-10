#requires -version 5.1
param([switch]$SelfTest)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$gamePath = Join-Path $packageRoot 'LittleBattlefield.exe'
$dataPath = Join-Path $packageRoot 'LittleBattlefield.pck'
$addressPath = Join-Path $packageRoot 'host-address.txt'
$versionPath = Join-Path $packageRoot 'VERSION.txt'
$version = if (Test-Path -LiteralPath $versionPath) { (Get-Content -LiteralPath $versionPath -Raw).Trim() } else { 'unknown' }

$form = New-Object System.Windows.Forms.Form
$form.Text = "小小战地 v$version | 加入局域网战役"
$form.ClientSize = New-Object System.Drawing.Size(470, 248)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)

$intro = New-Object System.Windows.Forms.Label
$intro.Text = '浏览局域网中的房间，或直接输入房主的 IPv4 地址。'
$intro.Location = New-Object System.Drawing.Point(20, 20)
$intro.Size = New-Object System.Drawing.Size(430, 42)
$form.Controls.Add($intro)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = '浏览局域网房间'
$browseButton.Location = New-Object System.Drawing.Point(20, 68)
$browseButton.Size = New-Object System.Drawing.Size(430, 40)
$form.Controls.Add($browseButton)
$form.AcceptButton = $browseButton

$addressLabel = New-Object System.Windows.Forms.Label
$addressLabel.Text = '房主地址（端口默认 27829）'
$addressLabel.Location = New-Object System.Drawing.Point(20, 121)
$addressLabel.Size = New-Object System.Drawing.Size(420, 24)
$form.Controls.Add($addressLabel)

$addressBox = New-Object System.Windows.Forms.TextBox
$addressBox.Location = New-Object System.Drawing.Point(20, 149)
$addressBox.Size = New-Object System.Drawing.Size(430, 29)
$addressBox.Text = if (Test-Path -LiteralPath $addressPath) { (Get-Content -LiteralPath $addressPath -Raw).Trim() } else { '' }
$form.Controls.Add($addressBox)

$hint = New-Object System.Windows.Forms.Label
$hint.Text = '手动地址会保存在此文件夹，供下次使用。'
$hint.Location = New-Object System.Drawing.Point(20, 190)
$hint.Size = New-Object System.Drawing.Size(320, 48)
$form.Controls.Add($hint)

$joinButton = New-Object System.Windows.Forms.Button
$joinButton.Text = '立即加入'
$joinButton.Location = New-Object System.Drawing.Point(345, 196)
$joinButton.Size = New-Object System.Drawing.Size(105, 38)
$form.Controls.Add($joinButton)

$browseButton.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath $gamePath) -or -not (Test-Path -LiteralPath $dataPath)) {
            throw '缺少游戏程序或数据包。请先完整解压 ZIP，再运行启动器。'
        }
        Start-Process -FilePath $gamePath -WorkingDirectory $packageRoot -ArgumentList @('--', '--lan-browser')
        $form.Close()
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '无法浏览房间', 'OK', 'Warning') | Out-Null
    }
})

$joinButton.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath $gamePath) -or -not (Test-Path -LiteralPath $dataPath)) {
            throw '缺少游戏程序或数据包。请先完整解压 ZIP，再运行启动器。'
        }
        $candidate = $addressBox.Text.Trim()
        if ($candidate -notmatch '^(\d{1,3}(?:\.\d{1,3}){3})(?::(\d{1,5}))?$') {
            throw '请输入 IPv4 地址，例如 192.168.1.8 或 192.168.1.8:27829。'
        }
        $ip = $null
        if (-not [System.Net.IPAddress]::TryParse($Matches[1], [ref]$ip) -or
            $ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
            throw 'IPv4 地址无效。'
        }
        $port = if ($Matches[2]) { [int]$Matches[2] } else { 27829 }
        if ($port -lt 1 -or $port -gt 65535) { throw '端口必须在 1 到 65535 之间。' }
        $endpoint = '{0}:{1}' -f $ip.ToString(), $port
        try { Set-Content -LiteralPath $addressPath -Value $endpoint -Encoding ASCII } catch { }
        Start-Process -FilePath $gamePath -WorkingDirectory $packageRoot -ArgumentList @('--', "--lan-join=$endpoint")
        $form.Close()
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '无法加入', 'OK', 'Warning') | Out-Null
    }
})

if ($SelfTest) { if (-not (Test-Path -LiteralPath $gamePath) -or -not (Test-Path -LiteralPath $dataPath)) { throw 'Package is missing its executable or data file.' }; Write-Output "Launcher UI ready for project v$version"; exit 0 }
[void]$form.ShowDialog()
