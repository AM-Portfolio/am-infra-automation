<#
.SYNOPSIS
  Post-restart staged warmup (generic): infra/platform gates, then ALL
  Deployments + StatefulSets in every non-system namespace, in batches.

  Discovers workloads live from the cluster - no hardcoded app name lists.
  Works for any fleet env (dev / preprod / prod / dr / custom).

.EXAMPLE
  .\warmup.ps1 -Env dev -BatchSize 5
  .\warmup.ps1 -Env preprod -BatchSize 5 -Kubeconfig $env:USERPROFILE\.asrax\kubeconfig.am-preprod-apps.yaml
  .\warmup.ps1 -Env prod -Namespaces am-apps-prod,am-agents-prod -BatchSize 5
#>
[CmdletBinding()]
param(
  [string] $Env = $(if ($env:WARMUP_ENV) { $env:WARMUP_ENV } else { "dev" }),
  [int] $BatchSize = $(if ($env:WARMUP_BATCH_SIZE) { [int]$env:WARMUP_BATCH_SIZE } else { 5 }),
  [int] $PerAppTimeoutSec = $(if ($env:WARMUP_PER_APP_TIMEOUT) { [int]$env:WARMUP_PER_APP_TIMEOUT } else { 480 }),
  [int] $GateTimeoutSec = $(if ($env:WARMUP_GATE_TIMEOUT) { [int]$env:WARMUP_GATE_TIMEOUT } else { 300 }),
  [string] $Kubeconfig = $(if ($env:WARMUP_KUBECONFIG) { $env:WARMUP_KUBECONFIG } else { "" }),
  [string] $InfraKubeconfig = $(if ($env:WARMUP_INFRA_KUBECONFIG) { $env:WARMUP_INFRA_KUBECONFIG } else { "" }),
  [string] $PlatformKubeconfig = $(if ($env:WARMUP_PLATFORM_KUBECONFIG) { $env:WARMUP_PLATFORM_KUBECONFIG } else { "" }),
  # Comma-separated. Empty = all namespaces except denylist.
  [string] $Namespaces = $(if ($env:WARMUP_NAMESPACES) { $env:WARMUP_NAMESPACES } else { "" }),
  # Comma-separated extra NS to skip (merged with built-in denylist).
  [string] $ExcludeNamespaces = $(if ($env:WARMUP_EXCLUDE_NAMESPACES) { $env:WARMUP_EXCLUDE_NAMESPACES } else { "" }),
  [switch] $SkipGates,
  [switch] $SkipWorkloads,
  [switch] $SkipBridgeRefresh,
  [switch] $DryRun,
  [string] $WarmupGeneration = $(if ($env:WARMUP_GENERATION) { $env:WARMUP_GENERATION } else { "" })
)

if ($env:WARMUP_SKIP_GATES -eq "1") { $SkipGates = $true }
if ($env:WARMUP_SKIP_WORKLOADS -eq "1" -or $env:WARMUP_SKIP_APPS -eq "1") { $SkipWorkloads = $true }
if ($env:WARMUP_SKIP_BRIDGE -eq "1") { $SkipBridgeRefresh = $true }
if ($env:WARMUP_DRY_RUN -eq "1") { $DryRun = $true }

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$ScriptDir = $PSScriptRoot
$TerraformRoot = (Resolve-Path (Join-Path $ScriptDir "..\..\..\..")).Path
$FleetRoot = Join-Path $TerraformRoot "kind-fleet"
$fleetEnvPs1 = Join-Path $FleetRoot "fleet-env.ps1"

# Built-in denylist: system / control-plane NS we never mass-restart in product warmup.
$BuiltinDeny = @(
  "kube-system", "kube-public", "kube-node-lease",
  "local-path-storage", "local-path-provisioner",
  "metallb-system", "cert-manager",
  "ingress-nginx", "traefik", "edge",
  "vault", "cnpg-system"
)

function Resolve-KubePaths {
  param([string] $FleetEnv)
  $apps = $Kubeconfig
  $infra = $InfraKubeconfig
  $plat = $PlatformKubeconfig
  if ((Test-Path -LiteralPath $fleetEnvPs1) -and ($FleetEnv -match '^(dev|prod|dr|preprod)$')) {
    . $fleetEnvPs1
    try {
      $f = Get-FleetEnv -Env $FleetEnv
      if (-not $apps) { $apps = $f.AppsKubeconfig }
      if (-not $infra) { $infra = $f.InfraKubeconfig }
      if (-not $plat) { $plat = $f.PlatformKubeconfig }
    } catch {
      # Get-FleetEnv may not accept preprod yet - fall through to path convention
    }
  }
  if (-not $apps) {
    $apps = Join-Path $env:USERPROFILE ".asrax\kubeconfig.am-$FleetEnv-apps.yaml"
  }
  if (-not $infra) {
    $infra = Join-Path $env:USERPROFILE ".asrax\kubeconfig.am-$FleetEnv-infra.yaml"
  }
  if (-not $plat) {
    $plat = Join-Path $env:USERPROFILE ".asrax\kubeconfig.am-$FleetEnv-platform.yaml"
  }
  return [pscustomobject]@{ Apps = $apps; Infra = $infra; Platform = $plat }
}

function Wait-KubectlReady {
  param(
    [string] $Kube,
    [string] $Namespace,
    [string] $Selector,
    [string] $Label,
    [int] $TimeoutSec = 300
  )
  if (-not (Test-Path -LiteralPath $Kube)) { Write-Warning "skip gate $Label (no kubeconfig)"; return }
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  do {
    $out = kubectl --kubeconfig $Kube -n $Namespace get pods -l $Selector --no-headers 2>$null
    $ok = $false
    foreach ($line in @($out)) {
      if ($line -match '^\S+\s+(\d+)/(\d+)\s+Running' -and $Matches[1] -eq $Matches[2] -and [int]$Matches[1] -gt 0) {
        $ok = $true
        break
      }
    }
    if ($ok) { Write-Host "gate ok: $Label"; return }
    Start-Sleep 5
  } while ((Get-Date) -lt $deadline)
  throw "gate timeout: $Label ($Selector in $Namespace)"
}

function Get-WorkloadNamespaces {
  param([string] $Kube)
  $deny = @($BuiltinDeny)
  if ($ExcludeNamespaces) {
    $deny += @($ExcludeNamespaces.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  }
  $denySet = [System.Collections.Generic.HashSet[string]]::new([string[]]$deny, [StringComparer]::OrdinalIgnoreCase)

  if ($Namespaces) {
    $list = @($Namespaces.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    return @($list | Where-Object { -not $denySet.Contains($_) } | Sort-Object)
  }

  $raw = kubectl --kubeconfig $Kube get ns -o json 2>$null | ConvertFrom-Json
  $names = @()
  foreach ($item in @($raw.items)) {
    $n = $item.metadata.name
    if ($denySet.Contains($n)) { continue }
    # Skip terminating
    if ($item.status.phase -eq "Terminating") { continue }
    $names += $n
  }
  return @($names | Sort-Object)
}

function Get-ClusterWorkloads {
  param([string] $Kube, [string[]] $NsList)
  # Returns list of @{ Kind; Namespace; Name }
  $workloads = @()
  foreach ($ns in $NsList) {
    foreach ($kind in @("deploy", "sts")) {
      $names = kubectl --kubeconfig $Kube -n $ns get $kind -o name 2>$null
      foreach ($line in @($names)) {
        $full = "$line".Trim()
        if (-not $full) { continue }
        # deployment.apps/foo or statefulset.apps/foo
        $name = ($full -replace '^(deployment|statefulset)\.apps/', '').Trim()
        if (-not $name) { continue }
        $k = if ($full -match '^statefulset') { "sts" } else { "deploy" }
        $workloads += [pscustomobject]@{ Kind = $k; Namespace = $ns; Name = $name }
      }
    }
  }
  # Stable order: namespace then kind then name
  return @($workloads | Sort-Object Namespace, Kind, Name)
}

function Clear-UnknownPods {
  param([string] $Kube, [string] $Ns, [string] $WorkloadName)
  $unkPods = kubectl --kubeconfig $Kube -n $Ns get pods --field-selector=status.phase=Unknown -o name 2>$null
  foreach ($p in @($unkPods)) {
    $pn = ("$p" -replace '^pod/', '').Trim()
    if (-not $pn) { continue }
    if ($pn -like "$WorkloadName*") {
      Write-Host "delete Unknown pod $Ns/$pn"
      if (-not $DryRun) {
        cmd /c "kubectl --kubeconfig `"$Kube`" -n $Ns delete pod $pn --wait=false" | Out-Null
      }
    }
  }
}

function Wait-WorkloadReady {
  param(
    [string] $Kube,
    [string] $Kind,
    [string] $Ns,
    [string] $Name,
    [int] $TimeoutSec
  )
  Write-Host "wait $Kind/$Name ($Ns) ..."
  if ($DryRun) { return }
  cmd /c "kubectl --kubeconfig `"$Kube`" -n $Ns rollout status $Kind/$Name --timeout=${TimeoutSec}s"
  if ($LASTEXITCODE -ne 0) {
    $pods = kubectl --kubeconfig $Kube -n $Ns get pods --no-headers 2>$null | Select-String $Name
    throw "$Kind/$Name not Ready after ${TimeoutSec}s :: $pods"
  }
}

function Invoke-BatchRestartWorkloads {
  param(
    [string] $Kube,
    [object[]] $Workloads,
    [int] $Chunk
  )
  if (-not $Workloads -or $Workloads.Count -eq 0) {
    Write-Host "no workloads to warm"
    return
  }
  Write-Host "warming $($Workloads.Count) workloads in batches of $Chunk"
  $batchNum = 0
  for ($i = 0; $i -lt $Workloads.Count; $i += $Chunk) {
    $batchNum++
    $slice = @($Workloads[$i..([Math]::Min($i + $Chunk - 1, $Workloads.Count - 1))])
    $desc = ($slice | ForEach-Object { "$($_.Namespace)/$($_.Kind)/$($_.Name)" }) -join ", "
    Write-Host "==== batch $batchNum ($($slice.Count)): $desc ===="
    foreach ($w in $slice) {
      Clear-UnknownPods -Kube $Kube -Ns $w.Namespace -WorkloadName $w.Name
      if ($DryRun) {
        Write-Host "[dry-run] rollout restart $($w.Kind)/$($w.Name) -n $($w.Namespace)"
        continue
      }
      cmd /c "kubectl --kubeconfig `"$Kube`" -n $($w.Namespace) rollout restart $($w.Kind)/$($w.Name)" | Out-Host
      if ($LASTEXITCODE -ne 0) {
        throw "rollout restart failed for $($w.Namespace)/$($w.Kind)/$($w.Name)"
      }
    }
    foreach ($w in $slice) {
      Wait-WorkloadReady -Kube $Kube -Kind $w.Kind -Ns $w.Namespace -Name $w.Name -TimeoutSec $PerAppTimeoutSec
    }
    Write-Host "==== batch $batchNum OK ===="
  }
}

# --- main ---
$paths = Resolve-KubePaths -FleetEnv $Env
$AppsKube = $paths.Apps
$InfraKube = $paths.Infra
$PlatKube = $paths.Platform
$RefreshScript = Join-Path $FleetRoot "$Env\obs\scripts\refresh-platform-bridges.ps1"
if (-not (Test-Path -LiteralPath $RefreshScript)) {
  # fallback: any env's refresh under kind-fleet/*/obs/scripts
  $alt = Get-ChildItem -Path $FleetRoot -Recurse -Filter "refresh-platform-bridges.ps1" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($alt) { $RefreshScript = $alt.FullName }
}

Write-Host "=== staged-workload-warmup START env=$Env batch=$BatchSize gen=$WarmupGeneration ==="
Write-Host "apps_kube=$AppsKube"

if (-not (Test-Path -LiteralPath $AppsKube)) { throw "missing apps kubeconfig $AppsKube" }

if (-not $SkipGates) {
  Write-Host "=== L0 infra gates ==="
  if (Test-Path -LiteralPath $InfraKube) {
    $vaultPod = kubectl --kubeconfig $InfraKube -n vault get pods --no-headers 2>$null
    if ("$vaultPod" -match 'Running') { Write-Host "gate ok: vault" }
    else { Write-Warning "Vault not Running on infra (continuing)" }
  } else {
    Write-Warning "no infra kubeconfig - skip vault gate"
  }
  $exposerName = "am-port-exposer"
  if ($Env -ne "dev") { $exposerName = "am-port-exposer-$Env" }
  $ex = docker inspect -f '{{.State.Running}}' am-port-exposer 2>$null
  if ($ex -ne "true") { $ex = docker inspect -f '{{.State.Running}}' $exposerName 2>$null }
  if ($ex -eq "true") { Write-Host "gate ok: exposer" }
  else { Write-Warning "port exposer not running (optional for non-laptop)" }

  $csiOk = $false
  foreach ($sel in @(
      "app.kubernetes.io/name=secrets-store-csi-driver",
      "app=secrets-store-csi-driver",
      "app.kubernetes.io/name=vault-csi-provider"
    )) {
    try {
      Wait-KubectlReady -Kube $AppsKube -Namespace "kube-system" -Selector $sel -Label "csi:$sel" -TimeoutSec 60
      $csiOk = $true
      break
    } catch { }
  }
  if (-not $csiOk) {
    $csiPods = kubectl --kubeconfig $AppsKube -n kube-system get pods --no-headers 2>$null | Select-String 'csi|secrets-store'
    if ("$csiPods" -match 'Running') { Write-Host "gate ok: csi (name match)" }
    else { Write-Warning "CSI not clearly Ready - continuing" }
  }

  Write-Host "=== L1 platform critical ==="
  if (Test-Path -LiteralPath $PlatKube) {
    foreach ($pair in @(
        @{ Ns = "identity"; Sel = "app.kubernetes.io/name=keycloak"; Label = "keycloak" },
        @{ Ns = "keycloak"; Sel = "app.kubernetes.io/name=keycloak"; Label = "keycloak" },
        @{ Ns = "argocd"; Sel = "app.kubernetes.io/name=argocd-server"; Label = "argocd-server" }
      )) {
      $nsHit = cmd /c "kubectl --kubeconfig `"$PlatKube`" get ns $($pair.Ns) -o name 2>nul"
      if (-not "$nsHit".Trim()) { continue }
      try {
        Wait-KubectlReady -Kube $PlatKube -Namespace $pair.Ns -Selector $pair.Sel -Label $pair.Label -TimeoutSec ([Math]::Min(120, $GateTimeoutSec))
      } catch {
        Write-Warning "gate $($pair.Label): $($_.Exception.Message)"
      }
    }
  } else {
    Write-Warning "no platform kubeconfig - skip L1"
  }

  Write-Host "=== L2 obs + bridges ==="
  if (-not $SkipBridgeRefresh -and $RefreshScript -and (Test-Path -LiteralPath $RefreshScript)) {
    & $RefreshScript -Env $Env
  }
  if (Test-Path -LiteralPath $PlatKube) {
    try {
      Wait-KubectlReady -Kube $PlatKube -Namespace "monitoring" -Selector "app.kubernetes.io/name=grafana" -Label "grafana" -TimeoutSec ([Math]::Min(120, $GateTimeoutSec))
    } catch {
      Write-Warning "grafana gate: $($_.Exception.Message)"
    }
  }
  try {
    $h = Invoke-WebRequest -Uri "https://grafana.asrax.in/api/health" -UseBasicParsing -TimeoutSec 20
    if ([int]$h.StatusCode -eq 200) { Write-Host "gate ok: grafana.asrax.in health 200" }
    else { Write-Warning "grafana.asrax.in health=$($h.StatusCode)" }
  } catch {
    Write-Warning "grafana.asrax.in health check skipped/failed: $($_.Exception.Message)"
  }
}

if (-not $SkipWorkloads) {
  Write-Host "=== discover workloads (all NS except denylist) ==="
  $nsList = Get-WorkloadNamespaces -Kube $AppsKube
  Write-Host "namespaces ($($nsList.Count)): $($nsList -join ', ')"
  $workloads = Get-ClusterWorkloads -Kube $AppsKube -NsList $nsList
  Write-Host "workloads found: $($workloads.Count) (deploy+sts)"
  Invoke-BatchRestartWorkloads -Kube $AppsKube -Workloads $workloads -Chunk $BatchSize
}

Write-Host "=== staged-workload-warmup DONE env=$Env ==="
exit 0
