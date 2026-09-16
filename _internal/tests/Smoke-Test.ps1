param([string]$TestDirectory=(Join-Path $env:TEMP ('CodexSwitcher-'+[Guid]::NewGuid().ToString('N'))))
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'core\Common.ps1')
if (Test-Path -LiteralPath $TestDirectory) { throw 'Use a new test directory.' }
$script:ProfileRoot=[IO.Path]::GetFullPath($TestDirectory)
$null=[IO.Directory]::CreateDirectory($script:ProfileRoot)
foreach($mode in @('OpenAI','DeepSeek')) {
    $path=Get-Target $mode; $null=[IO.Directory]::CreateDirectory($path)
    [IO.File]::WriteAllText((Join-Path $path 'config.toml'),'# isolated test config')
    # Normal nested Junctions are deliberately present during both switches.
    $cache=Join-Path $path 'plugins\cache'; $null=[IO.Directory]::CreateDirectory($cache)
    $null=New-Item -ItemType Junction -Path (Join-Path $cache 'legal-link') -Target $script:ProfileRoot
}
$null=New-Item -ItemType Junction -Path (Get-LinkPath) -Target (Get-Target OpenAI)
$results=@()
function Expect([bool]$Condition) { if (-not $Condition) { throw 'Check failed.' } }
function Refuses([scriptblock]$Action) { $refused=$false; try { & $Action } catch { $refused=$true }; Expect $refused }
function Check([string]$Name,[scriptblock]$Action) {
    & $Action
    Write-Host ('PASS - '+$Name)
    $script:results+=[pscustomobject]@{Test=$Name;Result='PASS';Scope='Isolated NTFS fixture; no app close/start'}
}
Check '1. Status OpenAI' { Expect ((Get-EnvironmentName) -eq 'OpenAI / ChatGPT') }
Check '2. OpenAI -> DeepSeek' { Switch-Junction DeepSeek; Confirm-Link (Get-Target DeepSeek) }
Check '3. Status DeepSeek' { Expect ((Get-EnvironmentName) -eq 'DeepSeek API') }
Check '4. DeepSeek -> OpenAI' { Switch-Junction OpenAI; Confirm-Link (Get-Target OpenAI) }
Check '5. Status OpenAI' { Expect ((Get-EnvironmentName) -eq 'OpenAI / ChatGPT') }
Check '6. Missing target stops safely' {
    $source=Get-Target DeepSeek; $saved=Join-Path $script:ProfileRoot 'deepseek-preserved'
    # Both explicitly checked paths are direct children of this new fixture root.
    Expect ([IO.Path]::GetDirectoryName($source) -eq $script:ProfileRoot)
    Expect ([IO.Path]::GetDirectoryName($saved) -eq $script:ProfileRoot)
    [IO.Directory]::Move($source,$saved)
    Refuses { Switch-Junction DeepSeek }; Confirm-Link (Get-Target OpenAI)
    [IO.Directory]::Move($saved,$source)
}
Check '7. Real .codex stops safely' {
    $source=Get-LinkPath; $saved=Join-Path $script:ProfileRoot 'saved-junction'
    Expect ([IO.Path]::GetDirectoryName($source) -eq $script:ProfileRoot)
    Expect ([IO.Path]::GetDirectoryName($saved) -eq $script:ProfileRoot)
    [IO.Directory]::Move($source,$saved)
    $null=[IO.Directory]::CreateDirectory($source)
    [IO.File]::WriteAllText((Join-Path $source 'keep.txt'),'preserve')
    Refuses { Switch-Junction DeepSeek }
    Expect ([IO.File]::ReadAllText((Join-Path $source 'keep.txt')) -eq 'preserve')
}
$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $TestDirectory 'smoke-results.json') -Encoding UTF8
Write-Host ('Seven checks passed. Test data retained at '+$TestDirectory)
