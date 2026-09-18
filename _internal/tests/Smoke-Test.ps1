param([string]$TestDirectory=(Join-Path $env:TEMP ('CodexSwitcher-v2-'+[Guid]::NewGuid().ToString('N'))))
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'core\Common.ps1')
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'core\ThirdParty.ps1')
if (Test-Path -LiteralPath $TestDirectory) { throw 'Use a new isolated test directory.' }
$script:ProfileRoot=[IO.Path]::GetFullPath($TestDirectory)
$null=[IO.Directory]::CreateDirectory($script:ProfileRoot)
$results=@()
function Expect([bool]$Condition) { if (-not $Condition) { throw 'Check failed.' } }
function Refuses([scriptblock]$Action) { $refused=$false; try { & $Action } catch { $refused=$true }; Expect $refused }
function Check([string]$Name,[scriptblock]$Action) { & $Action; Write-Host ('PASS - '+$Name); $script:results+=[pscustomobject]@{Test=$Name;Result='PASS'} }
foreach($mode in @('OpenAI','DeepSeek')) {
    $path=Get-Target $mode; $null=[IO.Directory]::CreateDirectory($path)
    [IO.File]::WriteAllText((Join-Path $path 'config.toml'),"model = 'deepseek-flash'`nmodel_provider = 'deepseek'`n[mcp_servers.keep]`ncommand = 'keep-me'`n[projects.'C:/fixture']`ntrust_level = 'trusted'`n")
    [IO.File]::WriteAllText((Join-Path $path 'keep.txt'),'preserve')
}
$legacyHash=(Get-FileHash (Join-Path (Get-Target DeepSeek) 'config.toml')).Hash
$null=New-Item -ItemType Junction -Path (Get-LinkPath) -Target (Get-Target OpenAI)
Check 'OpenAI status' { Expect ((Get-EnvironmentName) -eq 'OpenAI / ChatGPT') }
Check 'Migration copies legacy and preserves source' {
    Initialize-ThirdParty Copy
    Expect ((Get-FileHash (Join-Path (Get-Target DeepSeek) 'config.toml')).Hash -eq $legacyHash)
    Expect ([IO.File]::ReadAllText((Join-Path (Get-Target ThirdParty) 'keep.txt')) -eq 'preserve')
    Assert-ThirdPartyConfig
}
Check 'Existing ThirdParty no overwrite' {
    & $script:RouterExe select --home (Get-Target ThirdParty) --model k3-256k --effort low
    Expect ($LASTEXITCODE -eq 0)
    $before=(Get-FileHash (Join-Path (Get-Target ThirdParty) 'config.toml')).Hash
    Initialize-ThirdParty Copy
    Expect ((Get-FileHash (Join-Path (Get-Target ThirdParty) 'config.toml')).Hash -eq $before)
}
Check 'Nested junction allowed' {
    $null=New-Item -ItemType Junction -Path (Join-Path (Get-Target ThirdParty) 'legal-link') -Target (Get-Target OpenAI)
    Assert-Environment ThirdParty
}
Check 'OpenAI -> ThirdParty' { Switch-Junction ThirdParty; Confirm-Link (Get-Target ThirdParty) }
Check 'ThirdParty status' { Expect ((Get-EnvironmentName) -eq 'Third Party') }
Check 'ThirdParty -> OpenAI' { Switch-Junction OpenAI; Confirm-Link (Get-Target OpenAI) }
Check 'Legacy Junction handling' { Switch-Junction DeepSeek; Expect ((Get-EnvironmentName) -eq 'DeepSeek (Legacy)'); Switch-Junction ThirdParty; Switch-Junction OpenAI }
Check 'Unknown Junction refusal' {
    Remove-TopJunction (Get-Target OpenAI)
    $unknown=Join-Path $script:ProfileRoot 'unknown'; $null=New-Item -ItemType Directory -Path $unknown
    $null=New-Item -ItemType Junction -Path (Get-LinkPath) -Target $unknown
    Refuses { Switch-Junction ThirdParty }
    Remove-TopJunction $unknown
    $null=New-Item -ItemType Junction -Path (Get-LinkPath) -Target (Get-Target OpenAI)
}
Check 'Missing target preserves Junction' {
    $source=Get-Target ThirdParty; $saved=Join-Path $script:ProfileRoot 'saved-thirdparty'
    Expect ([IO.Path]::GetDirectoryName($source) -eq $script:ProfileRoot)
    Expect ([IO.Path]::GetDirectoryName($saved) -eq $script:ProfileRoot)
    [IO.Directory]::Move($source,$saved)
    try { Refuses { Switch-Junction ThirdParty }; Confirm-Link (Get-Target OpenAI) } finally { [IO.Directory]::Move($saved,$source) }
}
# Use an OS-assigned test port, never the production Router port.
$listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
$listener.Start(); $script:TestPort=$listener.LocalEndpoint.Port; $listener.Stop()
$script:TestInfo=Get-RouterInfo; $script:TestInfo.port=$script:TestPort
function Get-RouterInfo { return $script:TestInfo }
try {
    Check 'Router start and health' { Start-ThirdPartyRouter; Expect ((Get-RouterStatus) -eq 'Running') }
    Check 'Router reuse' { $first=(Get-RouterHealth).pid; Start-ThirdPartyRouter; Expect ((Get-RouterHealth).pid -eq $first) }
    Check 'Router stop' { Stop-ThirdPartyRouter; Expect ((Get-RouterStatus) -eq 'Stopped') }
    Check 'Unknown port occupant refusal' {
        $occupied=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$script:TestPort); $occupied.Start()
        try { Refuses { Start-ThirdPartyRouter }; Expect ($occupied.Server.IsBound) } finally { $occupied.Stop() }
    }
} finally { Stop-ThirdPartyRouter }
Check 'Real .codex directory preserved' {
    Remove-TopJunction (Get-Target OpenAI)
    $null=New-Item -ItemType Directory -Path (Get-LinkPath)
    $keep=Join-Path (Get-LinkPath) 'keep.txt'; [IO.File]::WriteAllText($keep,'preserve')
    Refuses { Switch-Junction ThirdParty }; Expect ([IO.File]::ReadAllText($keep) -eq 'preserve')
}
Check 'Process ownership remains narrow' {
    $p=[pscustomobject]@{Name='node.exe';ExecutablePath='C:\unrelated\node.exe';CommandLine='node C:\unrelated\server.js';ProcessId=987654}
    Expect ((Get-ProcessKind $p) -eq '')
    $p.Name='powershell.exe'; $p.CommandLine=(Join-Path (Get-Target ThirdParty) 'helper.ps1')
    Expect ((Get-ProcessKind $p) -eq '')
    Expect (Test-CodexPath (Join-Path (Get-Target ThirdParty) 'helper.exe'))
    Expect (Test-CodexPath (Join-Path (Get-Target DeepSeek) 'helper.exe'))
}
Check 'Unverified health PID cannot claim ownership' {
    Expect (-not (Test-OwnedRouter ([pscustomobject]@{service='CodexSwitcher Router';status='ok';version=(Get-RouterInfo).version;pid=$PID})))
}
Check 'Router mock integration suite' {
    & (Join-Path $PSScriptRoot 'Router.Tests.exe') '-test.v'
    Expect ($LASTEXITCODE -eq 0)
}
$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $TestDirectory 'smoke-results.json') -Encoding UTF8
Write-Host ($results.Count.ToString()+' smoke checks passed. Fixture retained at '+$TestDirectory)
