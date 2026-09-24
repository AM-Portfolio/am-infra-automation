<#
.SYNOPSIS
  Thin wrapper: laptop-dev fresh redeploy. Prefer fresh-redeploy.ps1 -Env <env> for other envs.
#>
[CmdletBinding()]
param(
  [switch] $Force,
  [switch] $SkipBackup,
  [switch] $SkipWipe,
  [switch] $SkipTerraform,
  [switch] $SkipPin,
  [switch] $SkipSync,
  [switch] $SkipSmoke,
  [ValidateSet("W1", "W2", "W3", "W4")]
  [string] $StartFromWave = "W1",
  [int] $PerAppTimeoutSec = 480,
  [int] $BatchSize = 3
)

& (Join-Path $PSScriptRoot "fresh-redeploy.ps1") `
  -Env dev `
  -Force:$Force `
  -SkipBackup:$SkipBackup `
  -SkipWipe:$SkipWipe `
  -SkipTerraform:$SkipTerraform `
  -SkipPin:$SkipPin `
  -SkipSync:$SkipSync `
  -SkipSmoke:$SkipSmoke `
  -StartFromWave $StartFromWave `
  -PerAppTimeoutSec $PerAppTimeoutSec `
  -BatchSize $BatchSize

exit $LASTEXITCODE
