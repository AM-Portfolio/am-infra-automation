# Finish laptop colocate: Keycloak realm (PF fallback) + Argo CD on am-dev-infra
$ErrorActionPreference = "Continue"
$gitRoot = "C:\Program Files\Git"
$env:PATH = "$gitRoot\bin;$gitRoot\usr\bin;" + $env:PATH
$KcInfra = Join-Path $env:USERPROFILE ".asrax\kubeconfig.am-dev-infra.yaml"
$env:KUBECONFIG = $KcInfra

$Plat = "f:\am-repos\am-repos\am-infra-automation\terraform\kind-fleet\dev\platform"
$StateDir = Join-Path $env:USERPROFILE ".asrax\tfstate\dev\platform"
$tfvarsPath = Join-Path $StateDir "colocate.auto.tfvars"
if (-not (Test-Path $tfvarsPath)) { throw "missing $tfvarsPath" }

kubectl --kubeconfig $KcInfra -n identity wait --for=condition=ready pod/keycloak-0 --timeout=120s
if ($LASTEXITCODE -ne 0) { throw "keycloak not ready" }

Push-Location $Plat
try {
  # Realm may be incomplete after kill; replace then apply Argo + rest
  terraform.exe apply "-input=false" "-no-color" "-var-file=$tfvarsPath" `
    "-replace=module.keycloak.null_resource.realm_and_clients[0]" `
    "-auto-approve" 2>&1 |
    Tee-Object -FilePath "$StateDir\argocd-apply.log" | Out-Host
  $code = $LASTEXITCODE
  Write-Host "APPLY_EXIT=$code"
  if ($code -ne 0) { throw "apply failed exit=$code" }
} finally {
  Pop-Location
}

Write-Host "=== argocd ==="
kubectl --kubeconfig $KcInfra -n argocd get pods,svc,ingressroute.traefik.io 2>&1 | Out-Host
Write-Host "DEV_ARGO_APPLY_DONE"
