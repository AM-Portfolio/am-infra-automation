#Requires -Version 5.1
<#
.SYNOPSIS
  Resolve dig/dev vs local Kind agents fallback; manage hosts for am-dev.asrax.in.

.DESCRIPTION
  Probe dig via kubeconfig.dev / kubeapi-dev (never via overridden am-dev hosts).
  When dig unhealthy (or -ForceTarget local): ensure local Kind, apply hosts
  am-dev.asrax.in - 127.0.0.1, set KUBECONFIG to kubeconfig.agents.local.
  When dig healthy (or -ForceTarget dig): remove hosts block, use kubeconfig.dev.

  QA UI / local Kind use https://qa-dev.asrax.in/qa (hosts override). Dig apps stay am-dev.

.PARAMETER ForceTarget
  dig | local - skip probe.

.PARAMETER EnvOnly
  Print shell exports only (PowerShell: Invoke-Expression (.\resolve-dev-target.ps1 -EnvOnly)).

.EXAMPLE
  powershell -File resolve-dev-target.ps1
  powershell -File resolve-dev-target.ps1 -ForceTarget local
  powershell -File resolve-dev-target.ps1 -EnvOnly | Invoke-Expression
#>
param(
  [ValidateSet("auto", "dig", "local")]
  [string]$ForceTarget = "auto",
  [switch]$EnvOnly,
  [switch]$SkipEnsureKind
)

$ErrorActionPreference = "Stop"
$Asrax = Join-Path $env:USERPROFILE ".asrax"
$KcDig = Join-Path $Asrax "kubeconfig.dev"
$KcLocal = Join-Path $Asrax "kubeconfig.agents.local"
$HostsPath = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
$HostsFragment = Join-Path $Asrax "generated\am-agents-local-hosts.fragment"
$MarkerBegin = "# BEGIN am-agents-local-fallback"
$MarkerEnd = "# END am-agents-local-fallback"
$QaBase = "https://qa-dev.asrax.in/qa"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnsureScript = Join-Path $ScriptDir "ensure-agents-local-kind.ps1"

function Test-DigHealthy {
  if (-not (Test-Path $KcDig)) { return $false }
  $prev = $env:KUBECONFIG
  try {
    $env:KUBECONFIG = $KcDig
    $null = & kubectl --request-timeout=5s -n am-agents-dev get deploy am-qa-agents-dev -o name 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    # Prefer Ready replicas > 0 when present
    $ready = & kubectl --request-timeout=5s -n am-agents-dev get deploy am-qa-agents-dev -o jsonpath="{.status.readyReplicas}" 2>$null
    if ($ready -and [int]$ready -gt 0) { return $true }
    # Deploy exists but scaled to 0 - treat as unhealthy for QA HTTP fallback
    return $false
  } catch {
    return $false
  } finally {
    if ($null -ne $prev) { $env:KUBECONFIG = $prev } else { Remove-Item Env:KUBECONFIG -ErrorAction SilentlyContinue }
  }
}

function Set-HostsFallback([bool]$Enable) {
  New-Item -ItemType Directory -Force -Path (Split-Path $HostsFragment) | Out-Null
  $block = @"
$MarkerBegin
127.0.0.1 qa-dev.asrax.in
$MarkerEnd
"@
  Set-Content -Path $HostsFragment -Value $block -Encoding ascii

  if (-not (Test-Path $HostsPath)) {
    Write-Warning "Hosts file missing: $HostsPath"
    return
  }

  $raw = Get-Content -Path $HostsPath -Raw -ErrorAction SilentlyContinue
  if ($null -eq $raw) { $raw = "" }
  # Strip existing marked block
  $pattern = "(?ms)$([regex]::Escape($MarkerBegin)).*?$([regex]::Escape($MarkerEnd))\r?\n?"
  $cleaned = [regex]::Replace($raw, $pattern, "")

  if ($Enable) {
    if (-not $cleaned.EndsWith("`n")) { $cleaned += "`r`n" }
    $cleaned += $block + "`r`n"
  }

  try {
    Set-Content -Path $HostsPath -Value $cleaned -Encoding ascii -Force
  } catch {
    Write-Warning "Could not update $HostsPath (need Admin). Fragment written to $HostsFragment - merge manually."
    Write-Warning $_.Exception.Message
  }
}

function Write-Result([string]$Target) {
  if ($Target -eq "local") {
    $kc = $KcLocal
    $ns = "am-agents-local"
  } else {
    $kc = $KcDig
    $ns = "am-agents-dev"
  }
  $env:KUBECONFIG = $kc
  $env:AM_DEV_TARGET = $Target
  $env:AM_QA_BASE = $QaBase
  $env:QA_BASE_URL = $QaBase
  $env:AM_DEPLOY_KUBECONFIG = $kc

  if ($EnvOnly) {
    Write-Output "`$env:KUBECONFIG='$kc'"
    Write-Output "`$env:AM_DEV_TARGET='$Target'"
    Write-Output "`$env:AM_QA_BASE='$QaBase'"
    Write-Output "`$env:QA_BASE_URL='$QaBase'"
    Write-Output "`$env:AM_DEPLOY_KUBECONFIG='$kc'"
    Write-Output "`$env:AM_AGENTS_NAMESPACE='$ns'"
    return
  }

  Write-Host "dev-target=$Target"
  Write-Host "KUBECONFIG=$kc"
  Write-Host "AM_AGENTS_NAMESPACE=$ns"
  Write-Host "QA_BASE_URL=$QaBase"
}

# --- main ---
$forced = $env:AM_DEV_TARGET
if ($ForceTarget -eq "auto" -and $forced -in @("dig", "local")) {
  $ForceTarget = $forced
}

$target = $ForceTarget
if ($ForceTarget -eq "auto") {
  if (Test-DigHealthy) { $target = "dig" } else { $target = "local" }
}

if ($target -eq "local") {
  if (-not $SkipEnsureKind) {
    if (-not (Test-Path $KcLocal) -or -not (kind get clusters 2>$null | Select-String -SimpleMatch "am-agents-local")) {
      if (Test-Path $EnsureScript) {
        & powershell -NoProfile -File $EnsureScript
      } else {
        throw "Local Kind missing and ensure script not found: $EnsureScript"
      }
    }
  }
  Set-HostsFallback $true
} else {
  Set-HostsFallback $false
}

Write-Result $target
