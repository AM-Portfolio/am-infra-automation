# ==============================================================================
# AM-INFRA: Credential Synchronization Script (The "Makeup" Option)
# Usage: ./sync-creds.ps1
# Description: Synchronizes live Vault secrets with the credentials.txt reference.
# ==============================================================================

$root_domain = "munish.org"

# Use absolute path relative to the script location
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$creds_file = "$ScriptDir/../infrastructure-secrets/latest/credentials.txt"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host "🔄 Synchronizing Infrastructure Credentials..." -ForegroundColor Cyan

# 1. Verify Vault Connectivity
if (-not ($env:KUBECONFIG)) {
    $env:KUBECONFIG = "c:\Users\user\OneDrive\Documents\am-repos\am-infra\k8s\kubeconfig.vps"
}

function Get-VaultSecret {
    param($path, $field)
    $val = kubectl exec -n vault vault-0 -- vault kv get -field=$field $path 2>$null
    return $val
}

# 2. Fetch Values from Vault (No Hardcoded Secrets)
Write-Host "🔑 Fetching credentials from Vault..." -ForegroundColor Gray
$admin_pw = Get-VaultSecret "secret/infra/identity" "bootstrap_token"
$grafana_pw = Get-VaultSecret "secret/infra/monitoring/grafana" "password"
$postgres_pw = Get-VaultSecret "secret/infra/identity" "postgres_password"
$vault_token = "Run » kubectl get secret -n vault vault-auto-credentials -o jsonpath='{.data.root-token}' | base64 --decode"

$content = @"
================================================================================
  INFRASTRUCTURE ACCESS REFERENCE — am-infra
  [ENTERPRISE GITOPS DEPLOYMENT]
  LAST SYNCED: $timestamp

  ⚠️  LOCAL ADMIN REFERENCE: This file contains actual "Root Level" 
  credentials for your convenience. Keep this file secure.
================================================================================

AUTHENTIK IDENTITY HUB
  URL          : https://authentik.$root_domain
  Admin Portal : https://authentik.$root_domain/if/admin/

  ROLE: infra-admins (full access)
    Username : munish-admin
    Password : $admin_pw
    Vault Path: secret/infra/identity

  ROLE: infra-developers (read-only)
    Username : team-dev
    Password : Run » vault kv get -field=dev_password secret/infra/identity

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

INFRASTRUCTURE DASHBOARDS
  Grafana         → https://grafana.$root_domain
    Admin User    : admin
    Password      : $grafana_pw
    Vault Path    : secret/infra/monitoring/grafana

  InfluxDB        → https://influx.$root_domain
    Admin User    : admin
    Password      : Run » vault kv get -field=admin_password secret/infra/monitoring/influxdb

  MongoDB UI      → https://mongo.$root_domain
    Admin User    : root
    Password      : Run » vault kv get -field=password secret/infra/database/mongodb

  Traefik         → https://traefik.$root_domain/dashboard/
    Auth          : Linked to Authentik (OIDC)

  Headlamp (K8s)  → https://headlamp.$root_domain
    Auth          : Linked to Authentik (OIDC)

  Vault           → https://vault.$root_domain
    Admin Token   : $vault_token
    Auth          : Linked to Authentik (OIDC)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

DATABASE ROOT ACCESS
  PostgreSQL      : $postgres_pw

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

HOW TO RUN TERRAFORM
  Applying updates is fully autonomous:
    cd terraform/identity && terraform apply

================================================================================
"@

# 3. Write to File
if (-not (Test-Path "infrastructure-secrets/latest")) {
    New-Item -ItemType Directory -Path "infrastructure-secrets/latest" -Force
}

Set-Content -Path $creds_file -Value $content

Write-Host "✅ Sync Complete! Updated: $creds_file" -ForegroundColor Green
