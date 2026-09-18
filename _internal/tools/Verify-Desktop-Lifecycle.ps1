# Run only from an external terminal. This closes the hosting Codex app.
param([switch]$PauseForModelChecks)
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'core\Common.ps1')
Assert-ExternalTerminal
$root=Split-Path $PSScriptRoot -Parent
$report=Join-Path $root ('docs\desktop-lifecycle-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
$results=@()
foreach($mode in @('ThirdParty','OpenAI')) {
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'core\Switcher.ps1') -Mode $mode
    $code=$LASTEXITCODE
    $results+=[pscustomobject]@{Mode=$mode;ExitCode=$code;Time=(Get-Date).ToString('o')}
    $results | ConvertTo-Json | Set-Content -LiteralPath $report -Encoding UTF8
    if ($code -ne 0) { throw ('Lifecycle failed in '+$mode+'. Results: '+$report) }
    if ($mode -eq 'ThirdParty' -and $PauseForModelChecks) {
        Write-Host 'In Desktop, inspect the native model picker and try Kimi <-> DeepSeek in new conversations.'
        Write-Host 'Use short prompts. Router log records the actual model/provider; UI labels alone are not proof.'
        $null=Read-Host 'After recording the results, press Enter to return to OpenAI'
    }
}
Write-Host ('Lifecycle results: '+$report)
Write-Host 'This checks process startup and Junction state. It does not automatically certify model UI or API behavior.'
