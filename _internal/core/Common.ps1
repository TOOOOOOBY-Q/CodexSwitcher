# Windows PowerShell 5.1. Only the top-level .codex link is changed.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ProfileRoot = [Environment]::GetFolderPath('UserProfile')

function Get-Target([string]$Mode) { Join-Path $script:ProfileRoot ('.codex_' + $Mode.ToLowerInvariant()) }
function Get-LinkPath { Join-Path $script:ProfileRoot '.codex' }
function Get-LinkState {
    try { $item=Get-Item -LiteralPath (Get-LinkPath) -Force -ErrorAction Stop }
    catch [Management.Automation.ItemNotFoundException] { return [pscustomobject]@{Type='Missing';Target=''} }
    if (-not $item.PSIsContainer) { return [pscustomobject]@{Type='Other';Target=''} }
    if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return [pscustomobject]@{Type='Directory';Target=''} }
    if ($item.LinkType -ne 'Junction' -or @($item.Target).Count -ne 1) { return [pscustomobject]@{Type='Other reparse point';Target=''} }
    [pscustomobject]@{Type='Junction';Target=[IO.Path]::GetFullPath([string]@($item.Target)[0]).TrimEnd('\')}
}
function Get-EnvironmentName {
    $state=Get-LinkState
    if ($state.Type -eq 'Junction') {
        if ($state.Target -ieq (Get-Target OpenAI)) { return 'OpenAI / ChatGPT' }
        if ($state.Target -ieq (Get-Target DeepSeek)) { return 'DeepSeek API' }
    }
    return 'Unknown'
}
function Assert-Environment([string]$Mode) {
    $target=Get-Target $Mode
    $item=Get-Item -LiteralPath $target -Force -ErrorAction Stop
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Expected a real environment directory: $target" }
    if (-not (Test-Path -LiteralPath (Join-Path $target 'config.toml') -PathType Leaf)) { throw "Missing config.toml: $target" }
}
function Assert-SwitchReady {
    $state=Get-LinkState
    if ($state.Type -ne 'Junction') { throw '.codex must be a Junction. A real or missing directory is never removed.' }
    if ($state.Target -ine (Get-Target OpenAI) -and $state.Target -ine (Get-Target DeepSeek)) { throw 'Unknown current Junction target; nothing changed.' }
    Assert-Environment OpenAI
    Assert-Environment DeepSeek
    return $state
}
function Get-KeyState {
    foreach($scope in @('Process','User','Machine')) {
        if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY',$scope))) { return 'Present' }
    }
    return 'Missing'
}
function Confirm-Link([string]$Target) {
    $state=Get-LinkState
    if ($state.Type -ne 'Junction' -or $state.Target -ine $Target) { throw 'Junction target verification failed.' }
    if (-not (Test-Path -LiteralPath (Join-Path (Get-LinkPath) 'config.toml') -PathType Leaf)) { throw 'config.toml is not reachable through .codex.' }
}
function Remove-TopJunction([string]$ExpectedTarget) {
    $state=Get-LinkState
    if ($state.Type -ne 'Junction' -or $state.Target -ine $ExpectedTarget) { throw 'Junction changed or is a real directory. Removal refused.' }
    # Delete(path, false) removes this verified directory link only. Never recursive.
    [IO.Directory]::Delete((Get-LinkPath),$false)
    if ((Get-LinkState).Type -ne 'Missing') { throw '.codex still exists; stopped.' }
}
function Switch-Junction([string]$Mode) {
    $state=Assert-SwitchReady
    $target=Get-Target $Mode
    if ($state.Target -ieq $target) { Confirm-Link $target; return }
    $oldTarget=$state.Target; $created=$false
    Remove-TopJunction $oldTarget
    try {
        $null=New-Item -ItemType Junction -Path (Get-LinkPath) -Target $target -ErrorAction Stop
        $created=$true
        Confirm-Link $target
    } catch {
        # One simple rollback attempt. Never overwrite an unexpected occupant.
        try {
            $current=Get-LinkState
            if ($created -and $current.Type -eq 'Junction' -and $current.Target -ieq $target) { Remove-TopJunction $target }
            if ((Get-LinkState).Type -ne 'Missing') { throw 'Path occupied.' }
            $null=New-Item -ItemType Junction -Path (Get-LinkPath) -Target $oldTarget -ErrorAction Stop
            Confirm-Link $oldTarget
        } catch { throw "Switch failed. Both environments are preserved. Previous target: $oldTarget. Inspect .codex before retrying." }
        throw 'Switch failed; previous Junction restored. Codex was not started.'
    }
}

function Get-ProcessSnapshot { @(Get-CimInstance Win32_Process -ErrorAction Stop) }
function Test-CodexPath([string]$Text) {
    if (-not $Text) { return $false }
    $text=$Text.Replace('/','\')
    $root=[regex]::Escape($script:ProfileRoot)
    $local=[regex]::Escape((Join-Path $env:LOCALAPPDATA 'OpenAI\Codex'))
    return $text -match ('(?i)(?:'+$root+'\\\.codex(?:_openai|_deepseek)?|'+$local+')(?=\\|[\s"'']|$)')
}
function Get-ProcessKind($Process) {
    $name=[string]$Process.Name; $exe=[string]$Process.ExecutablePath
    # Never target Explorer, shells, the current process, or arbitrary system executables.
    if ($Process.ProcessId -eq $PID -or $name -match '^(explorer|powershell|pwsh|cmd)\.exe$') { return '' }
    if ($name -ieq 'msedge.exe') { return 'Edge' }
    $owned=(Test-CodexPath $exe) -or ($exe -match ('(?i)^'+[regex]::Escape($env:ProgramFiles)+'\\WindowsApps\\OpenAI\.Codex_[^\\]+\\'))
    if ($name -match '^(node|extension-host)\.exe$') {
        if (Test-CodexPath ([string]$Process.CommandLine)) { return 'Helper' }
        if (-not $Process.CommandLine -and $owned) { return 'Unknown' }
        return ''
    }
    if ($name -match '^(ChatGPT|codex|codex-.+|node_repl)\.exe$') {
        if (-not $exe) { return 'Unknown' }
        if ($owned) {
            if ($name -ieq 'ChatGPT.exe') { return 'Desktop' }
            if ($name -ieq 'codex.exe') { return 'Backend' }
            return 'Helper'
        }
    }
    return ''
}
function Get-CloseTargets($Snapshot) {
    foreach($p in $Snapshot) {
        $kind=Get-ProcessKind $p
        if ($kind) { [pscustomobject]@{Process=$p;Kind=$kind} }
    }
}
function Assert-ExternalTerminal {
    if ($env:CODEX_SHELL -or $env:CODEX_THREAD_ID -or $env:CODEX_SANDBOX) { throw 'Run this file from Explorer or a terminal outside Codex.' }
    $all=Get-ProcessSnapshot; $current=$PID; $seen=@{}
    while($current -and -not $seen.ContainsKey([string]$current)) {
        $seen[[string]$current]=$true
        $p=@($all | Where-Object {$_.ProcessId -eq $current})
        if (-not $p.Count) { break }
        if ($current -ne $PID -and (Get-ProcessKind $p[0]) -in @('Desktop','Backend')) { throw 'This terminal belongs to Codex. Run the entry from Explorer.' }
        $current=$p[0].ParentProcessId
    }
}
function Stop-OneProcess($Recorded,[switch]$Graceful) {
    $p=Get-Process -Id $Recorded.ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $p) { return }
    try {
        $null=$p.Handle
        if ([Math]::Abs(($p.StartTime.ToUniversalTime()-$Recorded.CreationDate.ToUniversalTime()).TotalSeconds) -gt 0.1) { return }
        if ($Graceful) { $null=$p.CloseMainWindow() } else { $p.Kill() }
    } catch { if (-not $p.HasExited) { Write-Host ('Could not close PID '+$Recorded.ProcessId+'. It will be checked again.') } }
    finally { $p.Dispose() }
}
function Close-CodexAndEdge {
    Write-Host 'Closing Codex and Microsoft Edge...'
    foreach($t in @(Get-CloseTargets (Get-ProcessSnapshot) | Where-Object {$_.Kind -in @('Desktop','Edge')})) { Stop-OneProcess $t.Process -Graceful }
    Start-Sleep -Seconds 1
    for($pass=0;$pass -lt 3;$pass++) {
        $targets=@(Get-CloseTargets (Get-ProcessSnapshot))
        if (-not $targets.Count) { Write-Host 'All Codex-related processes are stopped.'; return }
        # Edge first, then Codex and helpers; refresh on the next pass if a helper respawns.
        foreach($t in @($targets | Sort-Object @{Expression={if($_.Kind -eq 'Edge'){0}else{1}}})) {
            if ($t.Kind -ne 'Unknown') { Stop-OneProcess $t.Process }
        }
        Start-Sleep -Seconds 1
    }
    $left=@(Get-CloseTargets (Get-ProcessSnapshot))
    if ($left.Count) {
        Write-Host 'Some processes are still running:'
        $left | ForEach-Object {$_.Process | Select-Object Name,ProcessId} | Format-Table | Out-Host
        throw 'Close failed. No Junction was changed.'
    }
    Write-Host 'All Codex-related processes are stopped.'
}
function Start-CodexDesktop {
    $packages=@(Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction Stop)
    if ($packages.Count -ne 1) { throw 'Codex MSIX package not found; start Codex manually.' }
    $manifest=Get-AppxPackageManifest -Package $packages[0] -ErrorAction Stop
    $apps=@($manifest.Package.Applications.Application | Where-Object {$_.Executable -match 'ChatGPT\.exe$'})
    if ($apps.Count -ne 1) { throw 'Codex Desktop application entry not found.' }
    Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList ('shell:AppsFolder\'+$packages[0].PackageFamilyName+'!'+$apps[0].Id) -ErrorAction Stop
    for($i=0;$i -lt 20;$i++) {
        Start-Sleep -Milliseconds 500
        if (@(Get-ProcessSnapshot | Where-Object {(Get-ProcessKind $_) -eq 'Desktop'}).Count) { return }
    }
    throw 'Junction verified, but Desktop startup was not confirmed. Start Codex manually.'
}
