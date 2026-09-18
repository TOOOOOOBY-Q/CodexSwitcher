param([string]$Go='go')
$ErrorActionPreference='Stop'
$source=Join-Path (Split-Path $PSScriptRoot -Parent) 'router'
$output=Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\CodexSwitcherRouter.exe'
$env:CGO_ENABLED='0'
& $Go -C $source test -mod=vendor ./...
if ($LASTEXITCODE -ne 0) { throw 'Router tests failed.' }
& $Go -C $source build -mod=vendor -buildvcs=false -trimpath -ldflags '-s -w -buildid=' -o $output .
if ($LASTEXITCODE -ne 0) { throw 'Router build failed.' }
& $Go -C $source test -mod=vendor -c -trimpath -o (Join-Path (Split-Path $PSScriptRoot -Parent) 'tests\Router.Tests.exe')
if ($LASTEXITCODE -ne 0) { throw 'Router test executable build failed.' }
Get-FileHash -LiteralPath $output -Algorithm SHA256
