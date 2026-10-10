param(
    [string]$AssemblyPath='F:\steam\steamapps\common\Escape from Duckov\Duckov_Data\Managed\TeamSoda.Duckov.Core.dll',
    [string]$CecilPath='G:\I00009\client\unity\i07zjs2\Assets\KrolStudio\Plugins\Zenject\OptionalExtras\ReflectionBaking\Lib\Zenject.ReflectionBaking.Mono.Cecil.dll'
)
# Read-only symbol / call references. No game code execution or asset export.
Add-Type -LiteralPath $CecilPath
$referenceModule=[Zenject.ReflectionBaking.Mono.Cecil.ModuleDefinition]::ReadModule($AssemblyPath)
$selectedTypes=@('Grenade','Skill_Grenade','SkillContext','CA_Skill','SkillProjectileLineHUD','SkillHud3D')
$selectedMethods=@('CalculateVelocity','OnRelease','Launch','ReleaseSkill','LateUpdate','UpdateLine','CheckObsticle')
$observations=@()
foreach($referenceType in $referenceModule.Types) {
    if ($referenceType.Name -notin $selectedTypes) { continue }
    $methods=@()
    foreach($referenceMethod in $referenceType.Methods) {
        if ($referenceMethod.Name -notin $selectedMethods -or -not $referenceMethod.HasBody) { continue }
        $references=@($referenceMethod.Body.Instructions | Where-Object { $_.OpCode.Name -in @('call','callvirt','ldfld','stfld') } | ForEach-Object { $_.Operand.ToString() } | Select-Object -Unique)
        $methods+=@{name=$referenceMethod.Name;references=$references}
    }
    $observations+=@{type=$referenceType.FullName;fields=@($referenceType.Fields.Name);methods=$methods}
}
$report=@{source=$AssemblyPath;sha256=(Get-FileHash -LiteralPath $AssemblyPath -Algorithm SHA256).Hash;note='Read-only metadata / method references; not input bindings, serialized prefab values or in-game playtest.';types=$observations}
$output=Join-Path (Split-Path $PSScriptRoot) 'docs\duckov-throw-observations.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $output -Encoding utf8
if ($referenceModule -is [System.IDisposable]) { $referenceModule.Dispose() }
Write-Output "Recorded $($observations.Count) reference types to $output"
