# Phase 4a: seed apps/data/dev/* on laptop vault-dev.
# Source of truth is Terraform: kind-fleet/dev/vault-apps (+ module apps-vault-seed).
# This script only wraps terraform apply (same stores + vault token files as before).
# Uses cmd.exe for terraform on Windows (PowerShell arg parsing breaks flags).

$ErrorActionPreference = "Stop"
$fleetRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$stack = Join-Path $fleetRoot "dev\vault-apps"
$initBackend = Join-Path $fleetRoot "init-backend.ps1"

$storesEnv = "$env:USERPROFILE\.asrax\credentials.d\dev-infra-stores.env"
$vaultKeys = "$env:USERPROFILE\.asrax\vault-dev-infra.json"
if (-not (Test-Path $storesEnv)) { throw "missing $storesEnv" }
if (-not (Test-Path $vaultKeys)) { throw "missing $vaultKeys" }
if (-not (Test-Path $stack)) { throw "missing stack $stack" }

& $initBackend -Env dev -Role vault-apps
Push-Location $stack
try {
  cmd /c "terraform init -backend-config=backend.hcl -input=false"
  if ($LASTEXITCODE -ne 0) { throw "terraform init failed" }
  cmd /c "terraform apply -auto-approve -input=false"
  if ($LASTEXITCODE -ne 0) { throw "terraform apply failed" }
  cmd /c "terraform output -no-color"
} finally {
  Pop-Location
}

Write-Output "Seed complete (terraform kind-fleet/dev/vault-apps)."
