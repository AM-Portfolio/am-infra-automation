<#
.SYNOPSIS
  Thin wrapper: refresh cross-cluster bridges for this env.
#>
[CmdletBinding()]
param(
  [ValidateSet("dev", "preprod", "prod", "dr")]
  [string] $Env = "prod",
  [string] $InfraKubeconfig = "",
  [string] $Namespace = "infra"
)
$ErrorActionPreference = "Stop"
$central = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "scripts\refresh-cross-cluster-bridges.ps1"
& $central -Env $Env -InfraKubeconfig $InfraKubeconfig -Namespace $Namespace
