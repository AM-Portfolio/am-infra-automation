# ==============================================================================
# Secret Resolver Module — The "Smart Fishing" Layer
# ==============================================================================
# Implements the priority-based secret retrieval strategy:
#   1. Key Vault (HashiCorp Vault)
#   2. Kubernetes Secret
#   3. Environment / Fallback Value
# ==============================================================================



# ── 1. Vault Data Source ──────────────────────────────────────────────────────
data "vault_kv_secret_v2" "this" {
  count = (var.vault_path != "" && var.vault_enabled) ? 1 : 0
  mount = "secret"
  name  = var.vault_path
}

# ── 2. Kubernetes Data Source ─────────────────────────────────────────────────
data "kubernetes_secret" "this" {
  count = var.k8s_secret_name != "" ? 1 : 0
  metadata {
    name      = var.k8s_secret_name
    namespace = var.k8s_secret_namespace
  }
}

# ── 3. Smart Resolution Logic ─────────────────────────────────────────────────
locals {
  # Priority: Vault (if path provided) -> K8s (if name provided) -> Fallback
  resolved_value = coalesce(
    try(data.vault_kv_secret_v2.this[0].data[var.vault_key], null),
    try(data.kubernetes_secret.this[0].data[var.k8s_secret_key], null),
    var.fallback_value,
    "NOT_FOUND" 
  )
}

output "value" {
  description = "The final resolved secret value"
  value       = local.resolved_value
  sensitive   = true
}

output "source" {
  description = "Indicates where the secret was fished from"
  value = (
    try(data.vault_kv_secret_v2.this[0].data[var.vault_key], null) != null ? "VAULT" :
    try(data.kubernetes_secret.this[0].data[var.k8s_secret_key], null) != null ? "KUBERNETES" :
    var.fallback_value != "" ? "ENVIRONMENT" : "UNKNOWN"
  )
}
