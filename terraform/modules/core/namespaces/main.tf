# ------------------------------------------------------------------------------
# Core Kubernetes Namespaces Definitions
#
# ENVIRONMENT-AWARE NAMING:
#   - Core namespaces (identity, infra, monitoring, vault) are fixed names —
#     they don't change per environment because each environment gets its own
#     isolated Kind cluster.
#   - The app namespace IS environment-aware: am-apps-dev, am-apps-prod, etc.
# ------------------------------------------------------------------------------

variable "environment" {
  description = "Deployment environment name (local, preprod, prod, dev, dr, obs)"
  type        = string
  default     = "local"

  validation {
    condition     = contains(["local", "preprod", "prod", "dev", "dr", "obs"], var.environment)
    error_message = "environment must be one of: local, preprod, prod, dev, dr, obs."
  }
}

variable "create_identity" {
  type    = bool
  default = true
}

variable "create_apps" {
  type    = bool
  default = true
}

variable "create_github" {
  type    = bool
  default = true
}

variable "create_monitoring" {
  type    = bool
  default = true
}

variable "extra_namespaces" {
  description = "Optional extra namespaces (temporal, billing, growthbook, n8n, openproject, am-ai). Create on platform later."
  type        = list(string)
  default     = []
}

resource "kubernetes_namespace" "identity" {
  count    = var.create_identity ? 1 : 0
  metadata { name = "identity" }
}

resource "kubernetes_namespace" "infra" {
  metadata { name = "infra" }
}

resource "kubernetes_namespace" "monitoring" {
  count    = var.create_monitoring ? 1 : 0
  metadata { name = "monitoring" }
}

resource "kubernetes_namespace" "vault" {
  metadata { name = "vault" }
}

resource "kubernetes_namespace" "github_actions" {
  count    = var.create_github ? 1 : 0
  metadata { name = "github-actions" }
}

resource "kubernetes_namespace" "am_apps" {
  count = var.create_apps ? 1 : 0
  metadata {
    name = "am-apps-${var.environment}"
    labels = {
      environment = var.environment
      managed-by  = "terraform"
    }
  }
}

resource "kubernetes_service_account" "am_backend_sa" {
  count = var.create_apps ? 1 : 0
  metadata {
    name      = "am-backend-sa"
    namespace = kubernetes_namespace.am_apps[0].metadata[0].name
  }
  automount_service_account_token = true
  image_pull_secret { name = "github-registry-secret" }
  image_pull_secret { name = "regcred" }
  image_pull_secret { name = "ghcr-creds" }
  lifecycle {
    ignore_changes = [image_pull_secret]
  }
}

resource "kubernetes_namespace" "extra" {
  for_each = toset(var.extra_namespaces)
  metadata { name = each.value }
}

output "identity_ns" { value = var.create_identity ? kubernetes_namespace.identity[0].metadata[0].name : "" }
output "infra_ns" { value = kubernetes_namespace.infra.metadata[0].name }
output "monitoring_ns" { value = var.create_monitoring ? kubernetes_namespace.monitoring[0].metadata[0].name : "" }
output "vault_ns" { value = kubernetes_namespace.vault.metadata[0].name }
output "apps_ns" { value = var.create_apps ? kubernetes_namespace.am_apps[0].metadata[0].name : "" }
output "github_ns" { value = var.create_github ? kubernetes_namespace.github_actions[0].metadata[0].name : "" }
output "extra_ns" { value = { for k, ns in kubernetes_namespace.extra : k => ns.metadata[0].name } }



