param([string]$Model,[string]$Effort='high')
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'core\Common.ps1')
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'core\ThirdParty.ps1')
$mutex=New-Object Threading.Mutex($false,'Local\CodexSwitcher')
$locked=$false
try {
    try { $locked=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked=$true }
    if (-not $locked) { throw 'Another switch/close operation is running.' }
    $models=@((Get-RouterInfo).models)
    if (-not $Model) {
        for($i=0;$i -lt $models.Count;$i++) { Write-Host (($i+1).ToString()+'. '+$models[$i].name+' ('+$models[$i].id+')') }
        $choice=Read-Host 'Select model number'
        $number=0
        if (-not [int]::TryParse($choice,[ref]$number) -or $number -lt 1 -or $number -gt $models.Count) { throw 'Invalid selection.' }
        $Model=$models[$number-1].id
    }
    & $script:RouterExe select --home (Get-Target ThirdParty) --model $Model --effort $Effort
    if ($LASTEXITCODE -ne 0) { throw 'Model selection failed. Existing configuration preserved.' }
    Write-Host ('Selected '+$Model+'. Start a new conversation; restart Desktop if it still uses the previous model.')
    exit 0
} catch { Write-Host ('ERROR: '+$_.Exception.Message); exit 1 }
finally { if ($locked) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
