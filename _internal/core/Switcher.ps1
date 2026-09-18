param([Parameter(Mandatory=$true)][ValidateSet('OpenAI','ThirdParty')][string]$Mode,[switch]$LegacyDeepSeek)
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'ThirdParty.ps1')
$mutex=New-Object Threading.Mutex($false,'Local\CodexSwitcher')
$locked=$false
try {
    try { $locked=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked=$true }
    if (-not $locked) { throw 'Another switch/close operation is running.' }
    Assert-ExternalTerminal
    if ($Mode -eq 'ThirdParty') {
        Initialize-ThirdParty
        $null=Assert-SwitchReady $Mode
        if ($LegacyDeepSeek) { & $script:RouterExe select --home (Get-Target ThirdParty) --model deepseek-flash --effort high; if ($LASTEXITCODE -ne 0) { throw 'Legacy model selection failed.' } }
        Start-ThirdPartyRouter
    }
    $null=Assert-SwitchReady $Mode
    Close-CodexAndEdge
    if (@(Get-CloseTargets (Get-ProcessSnapshot)).Count) { throw 'A process restarted; stopped before changing the Junction.' }
    Switch-Junction $Mode
    if ($Mode -eq 'OpenAI') { Stop-ThirdPartyRouter }
    Start-CodexDesktop
    Confirm-Link (Get-Target $Mode)
    Write-Host ''
    Write-Host ('SUCCESS - '+(Get-EnvironmentName))
    exit 0
} catch { Write-Host ('ERROR: '+$_.Exception.Message); exit 1 }
finally { if ($locked) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
