<#
.SYNOPSIS
  Post-restart: refresh all infra Endpoints labeled am.io/bridge=cross-cluster
  to the live Kind node IP from Docker DNS (am.io/backend-host).

  Covers *-platform bridges and apps-traefik-bridge. Kubernetes Endpoints only
  accept IPs; never leave a stale 172.x from a prior Docker engine restart.
  Safe to re-run.

.EXAMPLE
  .\refresh-cross-cluster-bridges.ps1 -Env prod
  .\refresh-cross-cluster-bridges.ps1 -Env dev
#>
[CmdletBinding()]
param(
  [ValidateSet("dev", "preprod", "prod", "dr")]
  [string] $Env = "dev",
  [string] $InfraKubeconfig = "",
  [string] $Namespace = "infra"
)

$ErrorActionPreference = "Stop"

$FleetRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $FleetRoot "fleet-env.ps1")
$f = Get-FleetEnv -Env $Env

if (-not $InfraKubeconfig) { $InfraKubeconfig = $f.InfraKubeconfig }
if (-not (Test-Path -LiteralPath $InfraKubeconfig)) { throw "missing kubeconfig $InfraKubeconfig" }

function Get-DockerIp {
  param([string] $HostName)
  if (-not $HostName -or $HostName -eq "static-ip") { return $null }
  $ip = (docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $HostName 2>$null)
  if (-not $ip) { return $null }
  return $ip.Trim()
}

function Resolve-BackendHost {
  param(
    [string] $Name,
    [string] $LabelHost,
    [string] $FleetEnv
  )
  if ($LabelHost -and $LabelHost -ne "static-ip") { return $LabelHost }
  if ($Name -eq "apps-traefik-bridge") { return "am-$FleetEnv-apps-control-plane" }
  if ($Name -match '-platform$') { return "am-$FleetEnv-platform-control-plane" }
  return $null
}

# Prefer labeled bridges; fall back to all EPs + name heuristics if none labeled.
$epsJson = kubectl --kubeconfig $InfraKubeconfig -n $Namespace get endpoints -l "am.io/bridge=cross-cluster" -o json 2>$null
$eps = $null
if ($epsJson) {
  $eps = $epsJson | ConvertFrom-Json
}
if (-not $eps -or -not $eps.items -or @($eps.items).Count -eq 0) {
  $epsJson = kubectl --kubeconfig $InfraKubeconfig -n $Namespace get endpoints -o json
  $eps = $epsJson | ConvertFrom-Json
}
$items = @($eps.items)
if ($items.Count -eq 0) {
  Write-Warning "no Endpoints in $Namespace (label am.io/bridge=cross-cluster or all)"
  exit 0
}

$ipCache = @{}
$patched = 0
$ok = 0
$skipped = 0

foreach ($ep in $items) {
  $name = $ep.metadata.name
  $labels = $ep.metadata.labels
  $labelHost = $null
  if ($labels) {
    if ($labels.'am.io/backend-host') { $labelHost = [string]$labels.'am.io/backend-host' }
    elseif ($labels.PSObject.Properties['am.io/backend-host']) {
      $labelHost = [string]$labels.PSObject.Properties['am.io/backend-host'].Value
    }
  }
  # When listing all EPs (no label filter hit), only touch known bridge names.
  $bridgeLabel = $null
  if ($labels) {
    if ($labels.'am.io/bridge') { $bridgeLabel = [string]$labels.'am.io/bridge' }
  }
  $isBridge = ($bridgeLabel -eq "cross-cluster") -or ($name -eq "apps-traefik-bridge") -or ($name -match '-platform$')
  if (-not $isBridge) { continue }

  $backendHost = Resolve-BackendHost -Name $name -LabelHost $labelHost -FleetEnv $Env
  if (-not $backendHost -or $backendHost -eq "static-ip") {
    Write-Host "skip $name (static-ip or unknown backend-host)"
    $skipped++
    continue
  }

  if (-not $ipCache.ContainsKey($backendHost)) {
    $resolved = Get-DockerIp -HostName $backendHost
    if (-not $resolved) {
      Write-Warning "skip $name: docker inspect failed for $backendHost"
      $skipped++
      continue
    }
    $ipCache[$backendHost] = $resolved
  }
  $ip = $ipCache[$backendHost]

  $subsets = @($ep.subsets)
  if ($subsets.Count -lt 1 -or -not $subsets[0].ports -or $subsets[0].ports.Count -lt 1) {
    Write-Warning "skip $name (no subsets/ports)"
    $skipped++
    continue
  }
  $port = $subsets[0].ports[0].port
  $portName = $subsets[0].ports[0].name
  if (-not $portName) { $portName = "http" }
  $old = $null
  if ($subsets[0].addresses) { $old = $subsets[0].addresses[0].ip }
  if ($old -eq $ip) {
    Write-Host "ok $name already $ip`:$port (host=$backendHost)"
    $ok++
    continue
  }

  # Preserve existing labels; ensure bridge + backend-host are set.
  $labelMap = @{}
  if ($labels) {
    foreach ($p in $labels.PSObject.Properties) {
      if ($p.Name -and $p.Name -notmatch '^@') { $labelMap[$p.Name] = [string]$p.Value }
    }
  }
  $labelMap["am.io/bridge"] = "cross-cluster"
  $labelMap["am.io/backend-host"] = $backendHost

  $bodyObj = [ordered]@{
    apiVersion = "v1"
    kind       = "Endpoints"
    metadata   = [ordered]@{
      name      = $name
      namespace = $Namespace
      labels    = $labelMap
    }
    subsets = @(
      [ordered]@{
        addresses = @(@{ ip = $ip })
        ports     = @(@{ name = $portName; port = [int]$port; protocol = "TCP" })
      }
    )
  }
  $body = $bodyObj | ConvertTo-Json -Depth 8 -Compress
  $tmp = Join-Path $env:TEMP "ep-$name.json"
  Set-Content -LiteralPath $tmp -Value $body -Encoding utf8
  kubectl --kubeconfig $InfraKubeconfig apply -f $tmp | Out-Host
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  Write-Host "patched $name $old -> $ip`:$port (host=$backendHost)"
  $patched++
}

Write-Host "refresh-cross-cluster-bridges done env=$Env patched=$patched ok=$ok skipped=$skipped"
exit 0
