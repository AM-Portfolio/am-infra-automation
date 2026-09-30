<#
.SYNOPSIS
  Compat shim → central refresh-cross-cluster-bridges.ps1
  Prefer: terraform/kind-fleet/scripts/refresh-cross-cluster-bridges.ps1
  Or env wrapper: terraform/kind-fleet/<env>/scripts/refresh-cross-cluster-bridges.ps1

.EXAMPLE
  .\refresh-platform-bridges.ps1
  .\refresh-platform-bridges.ps1 -Env dr
#>
[CmdletBinding()]
param(
  [ValidateSet("dev", "preprod", "prod", "dr")]
  [string] $Env = "dev",
  [string] $PlatformNode = "",
  [string] $InfraKubeconfig = "",
  [string] $Namespace = "infra"
)
$ErrorActionPreference = "Stop"
# this file: kind-fleet/dev/obs/scripts/ → fleet root is ../../../
$FleetRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$central = Join-Path $FleetRoot "scripts\refresh-cross-cluster-bridges.ps1"
# PlatformNode kept for callers; central resolves via am.io/backend-host / name fallback.
& $central -Env $Env -InfraKubeconfig $InfraKubeconfig -Namespace $Namespace
