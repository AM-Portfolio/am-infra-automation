# ==============================================================================
# ADMIN LAYER — Management & Visibility Tools
# ==============================================================================

variable "vault_enabled" {
  description = "Whether to attempt a Vault lookup. Set to false for initial bootstrap run."
  type        = bool
  default     = true
}

# 1. Resolve Headlamp Token (Vault -> K8s -> Env)
module "headlamp_token_resolver" {
  source = "../modules/core/secret-resolver"

  vault_path      = "${var.environment}/infra/admin"
  vault_key       = "headlamp_token"
  vault_enabled   = var.vault_enabled
  k8s_secret_name = "headlamp-token"
  fallback_value  = var.headlamp_token
}

# 2. Deploy Headlamp Cluster UI
module "headlamp" {
  source = "../modules/apps/headlamp"

  namespace   = "infra"
  root_domain = var.root_domain
  
  # We pass empty OIDC for this stage as it is Foundation-Level
  oidc_client_id     = ""
  oidc_client_secret = ""

  # Potentially pass the fished token if Headlamp supports it
  # (Currently the headlamp module creates its own, but we can extend it)
}

# 3. Persist Fished Token back to Vault (if it changed or is new)
resource "vault_kv_secret_v2" "headlamp_persistence" {
  mount = "secret"
  name  = "${var.environment}/infra/admin"

  data_json = jsonencode({
    headlamp_token = module.headlamp_token_resolver.value
  })

  # Only do this if we actually have Vault reachable
}
