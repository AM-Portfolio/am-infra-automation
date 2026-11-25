#Requires -Version 5.1
<#
.SYNOPSIS
  Ensure laptop Kind cluster am-agents-local for dig/dev agents fallback.

.DESCRIPTION
  Creates Kind + Traefik (hostPorts 80/443) + NS/SA + TLS secret for am-dev.asrax.in.
  Writes ~/.asrax/kubeconfig.agents.local (lab/fallback — not a day-to-day SoT file).
  Idempotent. Does NOT register Contabo Argo.

.EXAMPLE
  powershell -File am-infra-automation/scripts/kind-fleet/ensure-agents-local-kind.ps1
#>
$ErrorActionPreference = "Stop"

$ClusterName = "am-agents-local"
$Asrax = Join-Path $env:USERPROFILE ".asrax"
$KcOut = Join-Path $Asrax "kubeconfig.agents.local"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$KindCfg = Join-Path $ScriptDir "agents-local\kind-config.yaml"
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..\..\..")
$GitopsLocal = if ($env:AM_GITOPS_LOCAL -and (Test-Path $env:AM_GITOPS_LOCAL)) {
  $env:AM_GITOPS_LOCAL
} else {
  $cand = Join-Path $RepoRoot "am-gitops\manifests\local"
  if (-not (Test-Path $cand)) {
    $cand = Join-Path (Split-Path $RepoRoot -Parent) "am-gitops\manifests\local"
  }
  $cand
}
Write-Host "GitopsLocal=$GitopsLocal"

function Require-Cmd([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command not found: $Name"
  }
}

Require-Cmd kind
Require-Cmd kubectl
Require-Cmd helm
Require-Cmd docker

New-Item -ItemType Directory -Force -Path $Asrax | Out-Null

Write-Host "== 1) Kind cluster $ClusterName =="
$existing = @()
try {
  $existing = @(kind get clusters 2>&1 | Where-Object { $_ -and $_ -notmatch "No kind clusters" })
} catch {
  $existing = @()
}
$NodeImage = if ($env:KIND_NODE_IMAGE) { $env:KIND_NODE_IMAGE } else { "kindest/node:v1.29.14" }
if ($existing -notcontains $ClusterName) {
  if (-not (Test-Path $KindCfg)) { throw "Missing kind config: $KindCfg" }
  Write-Host "Using node image $NodeImage"
  kind create cluster --name $ClusterName --config $KindCfg --image $NodeImage
  if ($LASTEXITCODE -ne 0) { throw "kind create failed" }
} else {
  Write-Host "Kind cluster already exists"
}

Write-Host "== 2) Write $KcOut =="
kind get kubeconfig --name $ClusterName | Set-Content -Path $KcOut -Encoding utf8
# Normalize context name
$env:KUBECONFIG = $KcOut
$ctx = (kubectl config current-context)
if ($ctx -ne "agents-local") {
  kubectl config rename-context $ctx agents-local 2>$null
  if ($LASTEXITCODE -ne 0) {
    # already renamed or kind-am-agents-local
    $names = @(kubectl config get-contexts -o name)
    $want = $names | Where-Object { $_ -match "agents-local|am-agents-local" } | Select-Object -First 1
    if ($want) { kubectl config use-context $want | Out-Null }
  } else {
    kubectl config use-context agents-local | Out-Null
  }
}
Write-Host "KUBECONFIG=$KcOut context=$(kubectl config current-context)"

Write-Host "== 3) Namespace + SA =="
$nsYaml = Join-Path $GitopsLocal "am-agents-local-minimal.yaml"
if (-not (Test-Path $nsYaml)) { throw "Missing $nsYaml" }
kubectl apply -f $nsYaml | Out-Host

Write-Host "== 4) ingress-nginx (Kind NodePorts 30080/30443) =="
# Dig uses Traefik; local Kind uses ingress-nginx for Windows + kubeVersion compatibility.
$nginxYaml = Join-Path $GitopsLocal "ingress-nginx-kind.yaml"
if (-not (Test-Path $nginxYaml)) { throw "Missing $nginxYaml" }
kubectl apply -f $nginxYaml | Out-Host
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=180s
if ($LASTEXITCODE -ne 0) { throw "ingress-nginx rollout failed" }

Write-Host "== 5) TLS secret am-dev.asrax.in =="
$TlsDir = Join-Path $env:TEMP "am-agents-local-tls"
New-Item -ItemType Directory -Force -Path $TlsDir | Out-Null
$Key = Join-Path $TlsDir "tls.key"
$Crt = Join-Path $TlsDir "tls.crt"
if (-not ((Test-Path $Crt) -and (Test-Path $Key))) {
  if (Get-Command openssl -ErrorAction SilentlyContinue) {
    & openssl req -x509 -nodes -days 825 -newkey rsa:2048 `
      -keyout $Key -out $Crt -subj "/CN=am-dev.asrax.in"
  } else {
    # Docker openssl (Windows path → /out)
    $mount = ($TlsDir -replace '\\', '/')
    if ($mount -match '^[A-Za-z]:') {
      $mount = "/" + $mount.Substring(0, 1).ToLower() + $mount.Substring(2)
    }
    docker run --rm -v "${TlsDir}:/out" alpine/openssl req -x509 -nodes -days 825 -newkey rsa:2048 `
      -keyout /out/tls.key -out /out/tls.crt -subj "/CN=am-dev.asrax.in"
  }
}
if (-not ((Test-Path $Crt) -and (Test-Path $Key))) { throw "Failed to create TLS cert for am-dev.asrax.in" }
kubectl -n am-agents-local create secret tls am-dev-asrax-in-tls `
  --cert=$Crt --key=$Key --dry-run=client -o yaml | kubectl apply -f - | Out-Host

Write-Host "== 6) QA health stub Ingress =="
$stub = Join-Path $GitopsLocal "qa-health-stub.yaml"
if (Test-Path $stub) { kubectl apply -f $stub | Out-Host }
kubectl -n am-agents-local rollout status deploy/qa-health-stub --timeout=120s

Write-Host "== 7) Smoke =="
kubectl get ns am-agents-local
kubectl -n am-agents-local get sa,deploy,svc,ingress
kubectl -n ingress-nginx get deploy,svc,pods
Write-Host "OK ensure-agents-local-kind complete"
Write-Host "Next: resolve-dev-target.ps1 -ForceTarget local   # hosts → 127.0.0.1"
Write-Host "Then: curl.exe -k https://am-dev.asrax.in/qa/health"
