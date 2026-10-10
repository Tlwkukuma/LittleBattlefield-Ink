param(
    [string]$AssemblyPath='F:\steam\steamapps\common\Escape from Duckov\Duckov_Data\Managed\TeamSoda.Duckov.Core.dll',
    [string]$CecilPath='G:\I00009\client\unity\i07zjs2\Assets\KrolStudio\Plugins\Zenject\OptionalExtras\ReflectionBaking\Lib\Zenject.ReflectionBaking.Mono.Cecil.dll'
)
# Read-only metadata and call references; no game code or extracted art.
Add-Type -LiteralPath $CecilPath
$hudModule=[Zenject.ReflectionBaking.Mono.Cecil.ModuleDefinition]::ReadModule($AssemblyPath)
$hudTypes=@('ReloadHUD','ActionProgressHUD','AimMarker','ADSAimMarker','CA_Reload')
$hudMethods=@('Update','LateUpdate','SetAdsValue','SetScatter','OnActionStart','OnActionFinish','GetProgress','Reload')
$rows=@()
foreach($hudType in $hudModule.Types) {
    if ($hudType.Name -notin $hudTypes) {continue}
    $methods=@()
    foreach($hudMethod in $hudType.Methods) {
        if ($hudMethod.Name -notin $hudMethods -or -not $hudMethod.HasBody) {continue}
        $references=@($hudMethod.Body.Instructions | Where-Object {$_.OpCode.Name -in @('call','callvirt','ldfld','stfld','ldstr')} | ForEach-Object {$_.Operand.ToString()} | Select-Object -Unique)
        $methods+=@{name=$hudMethod.Name;references=$references}
    }
    $rows+=@{type=$hudType.FullName;fields=@($hudType.Fields.Name);methods=$methods}
}
$output=Join-Path (Split-Path $PSScriptRoot) 'docs\duckov-combat-hud-observations.json'
@{source=$AssemblyPath;sha256=(Get-FileHash -LiteralPath $AssemblyPath -Algorithm SHA256).Hash;note='Read-only symbols and call references, not measured screen appearance or input bindings.';types=$rows} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $output -Encoding utf8
Write-Output "Recorded $($rows.Count) HUD reference types to $output"
