<#
.SYNOPSIS
Enterprise Factory Reset Script
.DESCRIPTION
This script safely wipes local legacy Kubernetes clusters and Docker resources 
so Terraform can start from a clean 10/10 Enterprise state.
#>

$ErrorActionPreference = "Stop"

Write-Host "======================================================" -ForegroundColor Red
Write-Host " 🔥  ENTERPRISE FACTORY RESET (LOCAL CLEANUP) 🔥  " -ForegroundColor Red
Write-Host "======================================================" -ForegroundColor Red
Write-Host "This will delete your local 'am-preprod' Kind cluster and its data." -ForegroundColor Yellow
$confirm1 = Read-Host "Type 'YES' to proceed"

if ($confirm1 -cne "YES") {
    Write-Host "✅ Reset aborted. Your environment is safe." -ForegroundColor Green
    exit 0
}

$confirm2 = Read-Host "Are you absolutely sure? This CANNOT be undone. Type 'CONFIRM'"
if ($confirm2 -cne "CONFIRM") {
    Write-Host "✅ Reset aborted. Your environment is safe." -ForegroundColor Green
    exit 0
}

Write-Host "`n🔓 Security locks deactivated. NUKING LEGACY STATE...`n" -ForegroundColor Red

# 1. Delete Kind Cluster
Write-Host "[1/3] Deleting local KinD cluster 'am-preprod'..." -ForegroundColor Cyan
try {
    kind delete cluster --name am-preprod
} catch {
    Write-Host "Cluster already deleted or kind not found." -ForegroundColor DarkGray
}

# 2. Stop Port Exposer network container if running
Write-Host "[2/3] Cleaning up orphaned Docker networks/containers..." -ForegroundColor Cyan
try {
    docker rm -f am-port-forwarder 2>$null
    docker rm -f cloudflared-tunnel 2>$null
} catch {}

# 3. Clear local Terraform State (Optional but recommended for strict 10/10 reset)
$confirm3 = Read-Host "[3/3] Do you want to delete the local Terraform state to start 100% fresh? (y/n)"
if ($confirm3 -match "^[yY]$") {
    Write-Host "Clearing local terraform state..." -ForegroundColor Cyan
    if (Test-Path "terraform/environments/preprod/terraform.tfstate") {
        Remove-Item -Path "terraform/environments/preprod/terraform.tfstate*" -Force
    }
}

Write-Host "`n✅ FACTORY RESET COMPLETE. You are ready to run 'npm run apply'." -ForegroundColor Green
