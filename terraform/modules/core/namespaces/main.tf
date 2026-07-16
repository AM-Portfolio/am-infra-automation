# ------------------------------------------------------------------------------
# Core Kubernetes Namespaces Definitions
#
# ENVIRONMENT-AWARE NAMING:
#   - Core namespaces (identity, infra, monitoring, vault) are fixed names —
#     they don't change per environment because each environment gets its own
#     isolated Kind cluster.
#   - The app namespace IS environment-aware: am-apps-local, am-apps-preprod, etc.
#     This allows workloads and routing rules to be clearly environment-scoped.
# ------------------------------------------------------------------------------

variable "environment" {
  description = "Deployment environment name (local, preprod, prod)"
  type        = string
  default     = "local"
}

# 1. Identity Infrastructure
resource "kubernetes_namespace" "identity" {
  metadata { name = "identity" }
}

# 2. General Workloads & Databases
resource "kubernetes_namespace" "infra" {
  metadata { name = "infra" }
}

# 3. Observability & Monitoring
resource "kubernetes_namespace" "monitoring" {
  metadata { name = "monitoring" }
}

# 4. HashiCorp Vault (strict separation required)
resource "kubernetes_namespace" "vault" {
  metadata { name = "vault" }
}

# 5. GitHub Actions Runner
resource "kubernetes_namespace" "github_actions" {
  metadata { name = "github-actions" }
}

# 6. App Workloads — environment-scoped
#    local   → am-apps-local
#    preprod → am-apps-preprod
#    prod    → am-apps-prod
resource "kubernetes_namespace" "am_apps" {
  metadata {
    name = "am-apps-${var.environment}"
    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }
}

# ── Outputs ────────────────────────────────────────────────────────────────────
output "identity_ns"   { value = kubernetes_namespace.identity.metadata[0].name }
output "infra_ns"      { value = kubernetes_namespace.infra.metadata[0].name }
output "monitoring_ns" { value = kubernetes_namespace.monitoring.metadata[0].name }
output "vault_ns"      { value = kubernetes_namespace.vault.metadata[0].name }
output "apps_ns"       { value = kubernetes_namespace.am_apps.metadata[0].name }
output "github_ns"     { value = kubernetes_namespace.github_actions.metadata[0].name }
