. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'ThirdParty.ps1')
$mutex=New-Object Threading.Mutex($false,'Local\CodexSwitcher')
$locked=$false
try {
    try { $locked=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked=$true }
    if (-not $locked) { throw 'Another switch/close operation is running.' }
    Assert-ExternalTerminal
    Close-CodexAndEdge
    Stop-ThirdPartyRouter
    exit 0
} catch { Write-Host ('ERROR: '+$_.Exception.Message); exit 1 }
finally { if ($locked) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
