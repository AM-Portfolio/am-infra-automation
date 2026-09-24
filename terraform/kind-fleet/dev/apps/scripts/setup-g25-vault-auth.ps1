# Phase 4a G25: Vault CSI auth + GHCR pull secrets via Terraform (not kubectl).
# Source of truth: kind-fleet/dev/apps + modules/core/apps-vault-csi-auth
# Env-pluggable: .\setup-g25-vault-auth.ps1 -Env dev|prod|dr
# Uses cmd.exe for terraform on Windows (PowerShell arg parsing breaks flags).

[CmdletBinding()]
param(
  [Parameter()]
  [Alias("Env")]
  [ValidateSet("dev", "prod", "dr")]
  [string] $FleetEnv = "dev"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$fleetRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$stack = Join-Path $fleetRoot "$FleetEnv\apps"
$initBackend = Join-Path $fleetRoot "init-backend.ps1"

$vaultKeys = Join-Path $env:USERPROFILE ".asrax\vault-$FleetEnv-infra.json"
if ($FleetEnv -eq "dev") {
  $vaultKeys = Join-Path $env:USERPROFILE ".asrax\vault-dev-infra.json"
}
if (-not (Test-Path -LiteralPath $vaultKeys)) { throw "missing $vaultKeys" }
if (-not (Test-Path -LiteralPath $stack)) { throw "missing stack $stack" }
if (-not (Test-Path -LiteralPath $initBackend)) { throw "missing $initBackend" }

Write-Output "== G25 via terraform ($FleetEnv/apps module.vault_csi_auth) =="
& $initBackend -Env $FleetEnv -Role apps
Push-Location $stack
try {
  cmd /c "terraform init -backend-config=backend.hcl -input=false"
  if ($LASTEXITCODE -ne 0) { throw "terraform init failed" }

  # Adopt resources that may already exist from a prior kubectl G25 run (ignore failures).
  $imports = @(
    @("module.vault_csi_auth.vault_auth_backend.kubernetes_apps", "kubernetes-apps"),
    @("module.vault_csi_auth.vault_policy.am_apps_read", "am-apps-read"),
    @("module.vault_csi_auth.vault_kubernetes_auth_backend_role.am_backend", "auth/kubernetes-apps/role/am-backend-role"),
    @("module.vault_csi_auth.kubernetes_service_account_v1.vault_auth_reviewer", "kube-system/vault-auth-reviewer"),
    @("module.vault_csi_auth.kubernetes_cluster_role_binding_v1.vault_auth_reviewer", "vault-auth-reviewer-apps"),
    @("kubernetes_namespace.am_agents", "am-agents-dev"),
    @("kubernetes_namespace.am_apps", "am-apps-dev"),
    @("kubernetes_namespace.edge", "edge"),
    @("kubernetes_service_account.am_backend_sa", "am-apps-dev/am-backend-sa"),
    @("kubernetes_service_account.am_backend_sa_agents", "am-agents-dev/am-backend-sa")
  )
  foreach ($imp in $imports) {
    cmd /c ("terraform import -input=false " + $imp[0] + " " + $imp[1])
    # Ignore: already in state / does not exist / already managed
  }

  # Pull secrets already managed after first apply; import with safe quoting if needed.
  $secretPairs = @(
    "am-apps-dev.github-registry-secret",
    "am-apps-dev.regcred",
    "am-apps-dev.ghcr-creds",
    "am-agents-dev.github-registry-secret",
    "am-agents-dev.regcred",
    "am-agents-dev.ghcr-creds"
  )
  foreach ($pair in $secretPairs) {
    $dot = $pair.IndexOf(".")
    $ns = $pair.Substring(0, $dot)
    $name = $pair.Substring($dot + 1)
    $addr = 'module.vault_csi_auth.kubernetes_secret_v1.ghcr["' + $pair + '"]'
    $cmd = 'terraform import -input=false ' + $addr + ' ' + $ns + '/' + $name
    cmd /c $cmd
  }

  Write-Output "== terraform apply (G25 targets) =="
  cmd /c "terraform apply -auto-approve -input=false -target=module.vault_csi_auth -target=kubernetes_service_account.am_backend_sa -target=kubernetes_service_account.am_backend_sa_agents"
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "targeted apply failed; full apply"
    cmd /c "terraform apply -auto-approve -input=false"
    if ($LASTEXITCODE -ne 0) { throw "terraform apply failed" }
  }
  cmd /c "terraform output -no-color"
} finally {
  Pop-Location
}

Write-Output ("G25 auth done via terraform (env=$FleetEnv).")
exit 0
