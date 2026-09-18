# Windows PowerShell 5.1. Registry and TOML validation live in the Router binary.
$script:InternalRoot=Split-Path $PSScriptRoot -Parent
$script:RouterExe=Join-Path $script:InternalRoot 'bin\CodexSwitcherRouter.exe'
function Get-RouterInfo {
    if (-not (Test-Path -LiteralPath $script:RouterExe -PathType Leaf)) { throw 'Router executable missing. Use the complete Windows release package.' }
    $info=& $script:RouterExe info
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read Router registry.' }
    return ($info | ConvertFrom-Json)
}
function Get-RouterStateDirectory { Join-Path (Get-Target ThirdParty) '.switcher' }
function Get-RouterHealth {
    $info=Get-RouterInfo
    try { Invoke-RestMethod -Uri ('http://127.0.0.1:'+$info.port+'/healthz') -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop } catch { return $null }
}
function Test-OwnedRouter($Health) {
    if ($null -eq $Health) { return $false }
    try {
        if ($Health.service -ne 'CodexSwitcher Router' -or $Health.status -ne 'ok' -or $Health.version -ne (Get-RouterInfo).version) { return $false }
        $p=Get-Process -Id ([int]$Health.pid) -ErrorAction Stop
        return ($p.Path -ieq $script:RouterExe)
    } catch { return $false }
}
function Get-RouterStatus {
    $health=Get-RouterHealth
    if (Test-OwnedRouter $health) { return 'Running' }
    $port=(Get-RouterInfo).port
    $listeners=@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() | Where-Object {$_.Port -eq $port})
    if ($listeners.Count) { return 'Unhealthy' }
    return 'Stopped'
}
function Start-ThirdPartyRouter {
    $health=Get-RouterHealth
    if (Test-OwnedRouter $health) { return }
    if ((Get-RouterStatus) -ne 'Stopped') { throw 'Router port is occupied by an unknown or unhealthy program. Nothing was stopped.' }
    $saved=@{}
    try {
        foreach($name in @('KIMI_API_KEY','DEEPSEEK_API_KEY')) {
            $saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')
            foreach($scope in @('Process','User','Machine')) {
                $value=[Environment]::GetEnvironmentVariable($name,$scope)
                if (-not [string]::IsNullOrWhiteSpace($value)) { [Environment]::SetEnvironmentVariable($name,$value,'Process'); break }
            }
        }
        $state=Get-RouterStateDirectory
        $null=New-Item -ItemType Directory -Path $state -Force
        $p=Start-Process -FilePath $script:RouterExe -ArgumentList @('serve','--port',(Get-RouterInfo).port,'--state',('"'+$state+'"')) -WindowStyle Hidden -PassThru
    } finally { foreach($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }; $value=$null }
    for($i=0;$i -lt 30;$i++) {
        if ($p.HasExited) { throw 'Router exited before health verification. Check port occupancy and state directory access.' }
        $health=Get-RouterHealth
        if ((Test-OwnedRouter $health) -and $health.pid -eq $p.Id) { return }
        Start-Sleep -Milliseconds 100
    }
    if (-not $p.HasExited) { $p.Kill() }
    throw 'Router health check failed.'
}
function Stop-ThirdPartyRouter {
    $health=Get-RouterHealth
    $pidFile=Join-Path (Get-RouterStateDirectory) 'router.pid.json'
    $routerId=0
    if (Test-OwnedRouter $health) { $routerId=[int]$health.pid }
    elseif (Test-Path -LiteralPath $pidFile) {
        try { $record=Get-Content -LiteralPath $pidFile -Raw | ConvertFrom-Json; if ($record.executable -ieq $script:RouterExe) { $routerId=[int]$record.pid } } catch { return }
    }
    if (-not $routerId) { return }
    $p=Get-Process -Id $routerId -ErrorAction SilentlyContinue
    if ($null -eq $p) { return }
    try { $null=$p.Handle; if ($p.Path -ine $script:RouterExe) { return }; $p.Kill(); if (-not $p.WaitForExit(5000)) { throw 'Router did not stop.' } } finally { $p.Dispose() }
    if (Test-Path -LiteralPath $pidFile) { Remove-Item -LiteralPath $pidFile -Force }
}
function Assert-ThirdPartyConfig {
    & $script:RouterExe validate --home (Get-Target ThirdParty)
    if ($LASTEXITCODE -ne 0) { throw 'Third Party configuration is invalid; existing files were preserved.' }
}
function Initialize-ThirdParty([ValidateSet('Ask','Copy','Fresh')][string]$Migration='Ask') {
    $target=Get-Target ThirdParty
    if (Test-Path -LiteralPath $target) { Assert-Environment ThirdParty; Assert-ThirdPartyConfig; return }
    $legacy=Get-Target DeepSeek
    if ((Test-Path -LiteralPath $legacy) -and $Migration -eq 'Ask') {
        $answer=Read-Host 'Copy the existing .codex_deepseek into a new Third Party home? [Y/n]'
        if ($answer -eq '' -or $answer -match '^(y|yes)$') { $Migration='Copy' } else { $Migration='Fresh' }
    }
    $staging=Join-Path $script:ProfileRoot ('.codex_thirdparty.pending-'+[Guid]::NewGuid().ToString('N'))
    $null=New-Item -ItemType Directory -Path $staging
    if ((Test-Path -LiteralPath $legacy) -and $Migration -eq 'Copy') {
        Assert-Environment DeepSeek
        # /SJ and /SL preserve links without traversing plugin links or cycles.
        & robocopy.exe $legacy $staging /E /SJ /SL /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Migration copy failed. Legacy home is intact; partial copy retained at $staging" }
        if (-not (Test-Path -LiteralPath (Join-Path $staging 'config.toml'))) { throw 'Migration config copy is missing.' }
    }
    & $script:RouterExe init --home $staging --catalog-home $target
    if ($LASTEXITCODE -ne 0) { throw "Third Party preparation failed. Copy retained at $staging" }
    if ([IO.Path]::GetDirectoryName($staging) -ine $script:ProfileRoot -or [IO.Path]::GetDirectoryName($target) -ine $script:ProfileRoot) { throw 'Unexpected migration destination.' }
    if (Test-Path -LiteralPath $target) { throw 'Third Party appeared during migration; no overwrite.' }
    [IO.Directory]::Move($staging,$target)
    Assert-ThirdPartyConfig
}
