. (Join-Path $PSScriptRoot 'Common.ps1')
$failed=$false
Write-Host '========================================'
Write-Host ' Codex Environment'
Write-Host '========================================'
Write-Host ''
try { $state=Get-LinkState; $current=Get-EnvironmentName }
catch { $state=[pscustomobject]@{Type='Unknown';Target='Unknown'}; $current='Unknown'; $failed=$true }
Write-Host "Current:`n$current`n"
Write-Host ('.codex:'+"`n"+$state.Type+"`n")
Write-Host ("Target:`n"+$state.Target+"`n")
foreach($mode in @('OpenAI','DeepSeek')) {
    $present='Present'
    try { Assert-Environment $mode } catch { $present='Missing / unavailable'; $failed=$true }
    Write-Host ($mode+" environment:`n"+$present+"`n")
}
try { $key=Get-KeyState } catch { $key='Unknown'; $failed=$true }
Write-Host "DeepSeek API key:`n$key`n"
try {
    $kinds=@(Get-CloseTargets (Get-ProcessSnapshot) | ForEach-Object Kind)
    $desktop=if($kinds -contains 'Desktop'){'Running'}else{'Stopped'}
    $backend=if($kinds -contains 'Backend'){'Running'}else{'Stopped'}
    if ($kinds -contains 'Unknown') { $desktop='Unknown';$backend='Unknown';$failed=$true }
} catch { $desktop='Unknown';$backend='Unknown';$failed=$true }
Write-Host "Codex Desktop:`n$desktop`n"
Write-Host "Codex backend:`n$backend"
if ($failed) { exit 1 }
exit 0
