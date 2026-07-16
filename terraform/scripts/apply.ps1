#!/usr/bin/env pwsh
# ==============================================================================
# apply.ps1 — The ONE script you ever need to run
# ==============================================================================
# Usage:
#   ./scripts/apply.ps1              # Normal apply
#   ./scripts/apply.ps1 -Plan        # Plan only (no changes)
#   ./scripts/apply.ps1 -Module vault # Target a single module
#   ./scripts/apply.ps1 -Destroy     # Destroy (with confirmation)
# ==============================================================================

param(
  [switch]$Plan,
  [switch]$Destroy,
  [string]$Module = "",
  [switch]$AutoApprove
)

$ErrorActionPreference = "Stop"
$ENV_DIR = "$PSScriptRoot\..\environments\preprod"
$TERRAFORM = "$PSScriptRoot\..\terraform.exe"

# --- Resolve kubeconfig ---
$env:KUBECONFIG = "$PSScriptRoot\..\..\k8s\kubeconfig.vps"

# --- Load .env if present ---
$ENV_FILE = "$PSScriptRoot\..\..\.env"
if (Test-Path $ENV_FILE) {
    Write-Host "📦 Loading environment from .env..." -ForegroundColor Cyan
    Get-Content $ENV_FILE | ForEach-Object {
        if ($_ -match "^\s*([^#][^=]*)=(.*)$") {
            [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim())
        }
    }
}

# --- Navigate to environment ---
Push-Location $ENV_DIR

try {
    # Init (idempotent)
    Write-Host "🔧 Initializing Terraform..." -ForegroundColor Cyan
    & $TERRAFORM init -upgrade

    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ terraform init failed"
        exit 1
    }

    # Build target args
    $targetArgs = @()
    if ($Module -ne "") {
        $targetArgs += "-target=module.$Module"
        Write-Host "🎯 Targeting module: $Module" -ForegroundColor Yellow
    }

    # Plan
    if ($Plan -or !$AutoApprove) {
        Write-Host "📋 Running terraform plan..." -ForegroundColor Cyan
        & $TERRAFORM plan @targetArgs
        if ($LASTEXITCODE -ne 0) { Write-Error "❌ plan failed"; exit 1 }
        if ($Plan) { exit 0 }
    }

    # Destroy
    if ($Destroy) {
        Write-Host "💥 DESTROY mode — this will remove resources!" -ForegroundColor Red
        $confirm = Read-Host "Type 'yes' to confirm"
        if ($confirm -ne "yes") { Write-Host "Aborted."; exit 0 }
        & $TERRAFORM destroy @targetArgs -auto-approve
        exit $LASTEXITCODE
    }

    # Apply
    Write-Host "🚀 Applying infrastructure..." -ForegroundColor Green
    $applyArgs = @()
    if ($AutoApprove) { $applyArgs += "-auto-approve" }
    & $TERRAFORM apply @targetArgs @applyArgs

    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "✅ Infrastructure apply complete!" -ForegroundColor Green
        Write-Host "   Credentials file: infrastructure-secrets/latest/credentials.txt" -ForegroundColor Gray
    } else {
        Write-Error "❌ terraform apply failed"
        exit 1
    }
} finally {
    Pop-Location
}
