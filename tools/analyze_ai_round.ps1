param([ValidateSet(1,2,3)][int]$Round)
$projectPath = Split-Path -Parent $PSScriptRoot
$roundPath = Join-Path $projectPath "qa/ai-review/round-$Round"
$summary = Get-Content -LiteralPath (Join-Path $roundPath 'summary.json') -Raw | ConvertFrom-Json
$decisions = @(Get-Content -LiteralPath (Join-Path $roundPath 'events.jsonl') | Where-Object { $_ -match '"type":"ai_decision"' } | ForEach-Object { $_ | ConvertFrom-Json })
$responses = @($decisions | Where-Object { $_.source -eq 'laya' -and $_.raw_answers })
$latencies = @($responses | ForEach-Object { $_.latency_ms } | Sort-Object)
$accepted = @($responses | ForEach-Object { $_.choices.PSObject.Properties.Value } | Where-Object { $_.accepted })
$sampleRows = @(Get-Content -LiteralPath (Join-Path $roundPath 'samples.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
$states = @{}; $tasks = @{}; $sources = @{}; $progress = @(); $nextProgress = 0
foreach ($sample in $sampleRows) {
    $distances = @()
    foreach ($unit in $sample.units) {
        if (-not $unit.alive -or $unit.player) { continue }
        foreach ($pair in @(@($states,$unit.ai_state), @($tasks,$unit.ai_task), @($sources,$unit.ai_order.source))) {
            if ($null -ne $pair[1]) { $key = [string]$pair[1]; $pair[0][$key]++ }
        }
        if ($unit.team -eq 0) {
            $point = $sample.points[0].position
            $distances += [Math]::Sqrt([Math]::Pow($unit.position[0]-$point[0],2)+[Math]::Pow($unit.position[1]-$point[1],2))
        }
    }
    if ($sample.at -ge $nextProgress -and $distances.Count -gt 0) {
        $distances = @($distances | Sort-Object)
        $progress += [pscustomobject]@{at=$sample.at; blue_distance_median_m=$distances[[Math]::Floor($distances.Count/2)]; blue_nearest_m=$distances[0]; blue_alive=$distances.Count}
        $nextProgress += 20
    }
}
$report = [ordered]@{
    round=$Round; sim_seconds=$summary.sim_seconds; phase=$summary.phase; casualties=$summary.casualties
    shots=$summary.shots; point_unique_units=$summary.point_unique_units; trench_unique_units=$summary.trench_unique_units
    step_ms=$summary.step_ms; model_posts=@($decisions | Where-Object { $_.phase -eq 'request' }).Count
    actual_model_responses=$responses.Count; accepted_answers=$accepted.Count
    transport_errors=@($decisions | Where-Object { $_.phase -eq 'error' }).Count
    decision_rejections=@($decisions | Where-Object { $_.phase -eq 'rejected' }).Count
    decision_latency_p50_ms=$(if ($latencies.Count) { $latencies[[Math]::Floor($latencies.Count/2)] } else { $null })
    runtimes=@($responses | ForEach-Object { $_.runtime } | Select-Object -First 2)
    context_usage=@($responses | ForEach-Object { $_.contextUsage } | Select-Object -First 3)
    state_sample_counts=$states; task_sample_counts=$tasks; source_sample_counts=$sources; progress_samples=$progress
}
$json = $report | ConvertTo-Json -Depth 12
$json | Set-Content -LiteralPath (Join-Path $roundPath 'analysis.json') -Encoding utf8
$json
