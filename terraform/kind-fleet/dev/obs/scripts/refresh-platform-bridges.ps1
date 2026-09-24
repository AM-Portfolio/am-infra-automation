<#
.SYNOPSIS
  Post-restart: refresh infra Endpoints for all *-platform bridges to the live
  Kind platform node IP (Docker DNS: am-dev-platform-control-plane).

  Kubernetes Endpoints only accept IPs; never leave a stale 172.19.x from a prior
  Docker engine restart. Safe to re-run.

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

$FleetRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $FleetRoot "fleet-env.ps1")
$f = Get-FleetEnv -Env $Env

if (-not $PlatformNode) { $PlatformNode = "am-$Env-platform-control-plane" }
if (-not $InfraKubeconfig) { $InfraKubeconfig = $f.InfraKubeconfig }
if (-not (Test-Path -LiteralPath $InfraKubeconfig)) { throw "missing kubeconfig $InfraKubeconfig" }

$ip = (docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $PlatformNode 2>$null)
if (-not $ip) { throw "$PlatformNode not found on docker network (is Kind up?)" }
$ip = $ip.Trim()
Write-Host "platform_node=$PlatformNode ip=$ip"

$eps = kubectl --kubeconfig $InfraKubeconfig -n $Namespace get endpoints -o json | ConvertFrom-Json
$patched = 0
foreach ($ep in @($eps.items)) {
  $name = $ep.metadata.name
  if ($name -notmatch '-platform$') { continue }
  $subsets = @($ep.subsets)
  if ($subsets.Count -lt 1) {
    Write-Warning "skip $name (no subsets)"
    continue
  }
  $port = $subsets[0].ports[0].port
  $portName = $subsets[0].ports[0].name
  if (-not $portName) { $portName = "http" }
  $old = $null
  if ($subsets[0].addresses) { $old = $subsets[0].addresses[0].ip }
  if ($old -eq $ip) {
    Write-Host "ok $name already $ip`:$port"
    continue
  }
  $body = @{
    apiVersion = "v1"
    kind       = "Endpoints"
    metadata   = @{ name = $name; namespace = $Namespace }
    subsets    = @(
      @{
        addresses = @(@{ ip = $ip })
        ports     = @(@{ name = $portName; port = [int]$port; protocol = "TCP" })
      }
    )
  } | ConvertTo-Json -Depth 8 -Compress
  $tmp = Join-Path $env:TEMP "ep-$name.json"
  Set-Content -LiteralPath $tmp -Value $body -Encoding utf8
  kubectl --kubeconfig $InfraKubeconfig apply -f $tmp | Out-Host
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  Write-Host "patched $name $old -> $ip`:$port"
  $patched++
}

Write-Host "refresh-platform-bridges done (patched=$patched ip=$ip)"
exit 0
