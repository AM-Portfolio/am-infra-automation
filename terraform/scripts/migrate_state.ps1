# ------------------------------------------------------------------------------
# TERRAFORM STATE MIGRATION SCRIPT (HORIZONTAL TO VERTICAL)
# ------------------------------------------------------------------------------
# This script slides existing resource tracking from the root state into the 
# modular preprod environment state.

$TERRAFORM = "../../terraform.exe"
$SRC_STATE = "../../terraform.tfstate"
$KUBECONFIG = "c:\Users\user\OneDrive\Documents\am-repos\am-infra\k8s\kubeconfig.vps"
$env:KUBECONFIG = $KUBECONFIG

Write-Host "🚀 Starting State Migration..." -ForegroundColor Cyan

# 1. Namespaces
Write-Host "📦 Moving Core Namespaces..."
& $TERRAFORM state mv -state=$SRC_STATE "kubernetes_namespace.infra" "module.namespaces_core.kubernetes_namespace.infra"
& $TERRAFORM state mv -state=$SRC_STATE "kubernetes_namespace.monitoring" "module.namespaces_core.kubernetes_namespace.monitoring"
& $TERRAFORM state mv -state=$SRC_STATE "kubernetes_namespace.vault" "module.namespaces_core.kubernetes_namespace.vault"

# 2. Networking & Gateway
Write-Host "🌐 Moving Networking resources..."
& $TERRAFORM state mv -state=$SRC_STATE "helm_release.traefik" "module.traefik_core.helm_release.traefik"
& $TERRAFORM state mv -state=$SRC_STATE "kubernetes_config_map.traefik_dynamic" "module.traefik_core.kubernetes_config_map.traefik_dynamic"

# 3. Core Apps
Write-Host "🔐 Moving Vault..."
& $TERRAFORM state mv -state=$SRC_STATE "helm_release.vault" "module.vault.helm_release.vault"

Write-Host "✅ Migration Sequence Complete." -ForegroundColor Green
Write-Host "⚠️  Note: kubectl_manifest resources will be adopted by the new Helm modules via 'terraform apply'."
