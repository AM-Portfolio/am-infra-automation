# Resume laptop co_locate after /bin/bash PATH miss on first apply.
$ErrorActionPreference = "Continue"
$gitRoot = "C:\Program Files\Git"
if (-not (Test-Path "$gitRoot\bin\bash.exe")) { throw "Git bash missing at $gitRoot" }
# Terraform interpreter=/bin/bash resolves on Windows as C:\bin\bash (drive-relative).
if (-not (Test-Path "C:\bin\bash.exe")) {
  if (-not (Test-Path "C:\bin")) {
    cmd /c mklink /J C:\bin "C:\Program Files\Git\bin" | Out-Host
  }
  if (-not (Test-Path "C:\bin\bash.exe")) {
    New-Item -ItemType Directory -Force -Path C:\bin | Out-Null
    Copy-Item "$gitRoot\bin\bash.exe" "C:\bin\bash.exe" -Force
    Copy-Item "$gitRoot\bin\msys-*.dll" "C:\bin\" -Force -ErrorAction SilentlyContinue
  }
}
$env:PATH = "$gitRoot;$gitRoot\bin;$gitRoot\usr\bin;C:\bin;" + $env:PATH

$Plat = "f:\am-repos\am-repos\am-infra-automation\terraform\kind-fleet\dev\platform"
$StateDir = Join-Path $env:USERPROFILE ".asrax\tfstate\dev\platform"
$tfvarsPath = Join-Path $StateDir "colocate.auto.tfvars"
$KcInfra = Join-Path $env:USERPROFILE ".asrax\kubeconfig.am-dev-infra.yaml"

if (-not (Test-Path $tfvarsPath)) { throw "missing $tfvarsPath; re-run tmp-dev-colocate-apply.ps1 first" }

& "$gitRoot\bin\bash.exe" -c "echo PATH_BASH_OK"
kubectl --kubeconfig $KcInfra -n identity wait --for=condition=ready pod/keycloak-0 --timeout=180s
if ($LASTEXITCODE -ne 0) { throw "keycloak not ready" }

Push-Location $Plat
try {
  terraform.exe taint "module.keycloak.null_resource.realm_and_clients[0]" 2>$null
  terraform.exe taint "module.image_preload_3d.terraform_data.crictl_pull[0]" 2>$null
  terraform.exe plan "-input=false" "-no-color" "-var-file=$tfvarsPath" "-out=$StateDir\colocate-resume.tfplan" 2>&1 |
    Tee-Object -FilePath "$StateDir\colocate-resume-plan.log" | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "plan failed" }
  Select-String -Path "$StateDir\colocate-resume-plan.log" -Pattern "Plan:|Error:" | Select-Object -First 30 | Out-Host
  terraform.exe apply "-input=false" "-no-color" "$StateDir\colocate-resume.tfplan" 2>&1 |
    Tee-Object -FilePath "$StateDir\colocate-resume-apply.log" | Out-Host
  $code = $LASTEXITCODE
  Write-Host "APPLY_EXIT=$code"
  if ($code -ne 0) { throw "apply failed exit=$code" }
} finally {
  Pop-Location
}

kind get clusters
kubectl --kubeconfig $KcInfra -n identity get pods -o wide
kubectl --kubeconfig $KcInfra get ingressroute.traefik.io -A 2>$null | Select-Object -First 20
Write-Host "DEV_COLOCATE_RESUME_DONE"
