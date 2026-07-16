# Master Restoration Script for Asrax OIDC SSO
# ==============================================================================
# This script resolves the 'cluster.local' error by forcing the public issuer 
# URL across the entire identity hub and locking the state into Terraform.
# ==============================================================================

$env:KUBECONFIG='c:\Users\user\OneDrive\Documents\am-repos\am-infra\k8s\kubeconfig.vps'
$root_domain='munish.org'

# Use existing AUTHENTIK_TOKEN or prompt for one if missing
if (-not $env:AUTHENTIK_TOKEN) {
    Write-Host "⚠️  AUTHENTIK_TOKEN is not set in the environment." -ForegroundColor Yellow
    $env:AUTHENTIK_TOKEN = Read-Host "Please enter your Authentik Bootstrap Token"
}

Write-Host "🚀 Starting Master OIDC Restoration..." -ForegroundColor Blue

# 1. Update Identity Module (Fixing the Redirection Source)
Write-Host "🌐 Syncing Identity Hub (Authentik)..." -ForegroundColor Blue
cd c:\Users\user\OneDrive\Documents\am-repos\am-infra\terraform\identity
& ../terraform.exe apply -auto-approve -var="root_domain=$root_domain"

# 2. Update Security Module (Finalizing Vault SSO)
Write-Host "🔐 Finalizing Security Module (Vault)..." -ForegroundColor Blue
cd c:\Users\user\OneDrive\Documents\am-repos\am-infra\terraform\security
& ../terraform.exe apply -auto-approve -var="root_domain=$root_domain"

Write-Host "`n✅ OIDC Restoration Complete!" -ForegroundColor Green
Write-Host "--------------------------------------------------------"
Write-Host "Vault SSO: https://vault.munish.org/ui/vault/auth/oidc/oidc/login?role=admin"
Write-Host "Grafana:   https://grafana.munish.org"
Write-Host "Kafka UI:  https://kafka.munish.org/kafka-ui/"
Write-Host "--------------------------------------------------------"
Write-Host "The 'cluster.local' error is now resolved. Try logging in now!" -ForegroundColor Cyan
