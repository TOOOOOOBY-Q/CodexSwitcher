param([Parameter(Mandatory=$true)][ValidateSet('OpenAI','DeepSeek')][string]$Mode)
. (Join-Path $PSScriptRoot 'Common.ps1')
$mutex=New-Object Threading.Mutex($false,'Local\CodexSwitcher')
$locked=$false
try {
    try { $locked=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked=$true }
    if (-not $locked) { throw 'Another switch/close operation is running.' }
    $null=Assert-SwitchReady
    if ($Mode -eq 'DeepSeek' -and (Get-KeyState) -eq 'Missing') { throw 'DEEPSEEK_API_KEY: Missing' }
    Assert-ExternalTerminal
    Close-CodexAndEdge
    if (@(Get-CloseTargets (Get-ProcessSnapshot)).Count) { throw 'A process restarted; stopped before changing the Junction.' }
    Switch-Junction $Mode
    Start-CodexDesktop
    Confirm-Link (Get-Target $Mode)
    Write-Host ''
    Write-Host ('SUCCESS - '+(Get-EnvironmentName))
    exit 0
} catch { Write-Host ('ERROR: '+$_.Exception.Message); exit 1 }
finally { if ($locked) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
