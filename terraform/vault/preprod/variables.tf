# ==============================================================================
# VAULT LAYER VARIABLES (local entrypoint)
#
# SMART SECRET RESOLUTION:
# - If a variable is supplied via .env (manage.js injects as TF_VAR_*), that
#   value is used. It takes highest priority.
# - If a variable is empty (""), the vault/local/main.tf auto-generates a
#   random_password and seeds it into Vault instead.
# - After first boot, downstream layers should NEVER read these variables
#   directly. They must use: data "vault_kv_secret_v2" { ... }
# ==============================================================================

variable "root_domain" {
  type    = string
  default = "munish.org"
}

variable "environment" {
  type    = string
  default = "local"
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "/data/am-state/am-preprod-config"
}

variable "kubeconfig_context" {
  description = "Kubernetes context to use"
  type        = string
  default     = "am-preprod"
}

# The root token is required only on first boot to authenticate the vault
# provider so it can mount the KV engine. After that it lives in credentials.txt.
variable "vault_root_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "vault_unseal_key" {
  description = "The unseal key provided as a bootstrap seed from .env or local environment"
  type        = string
  sensitive   = true
  default     = ""
}

# ── Gateway ───────────────────────────────────────────────────────────────────
variable "cloudflare_api_token" {
  description = "Cloudflare API Token (or Global API Key if email is provided)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_email" {
  description = "Cloudflare Account Email (Required if using Global API Key)"
  type        = string
  default     = ""
}

variable "cloudflare_tunnel_token" {
  description = "Cloudflare Tunnel Token for the cloudflared runner"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_account_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "cloudflare_zone_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "cloudflare_tunnel_secret" {
  type      = string
  sensitive = true
  default   = ""   # Auto-generated if empty
}

# ── Databases ─────────────────────────────────────────────────────────────────
variable "postgresql_password" {
  type      = string
  sensitive = true
  default   = ""   # Auto-generated if empty
}

variable "mongodb_password" {
  type      = string
  sensitive = true
  default   = ""   # Auto-generated if empty
}

variable "redis_password" {
  type      = string
  sensitive = true
  default   = ""   # Auto-generated if empty
}

variable "influxdb_token" {
  type      = string
  sensitive = true
  default   = ""   # Auto-generated if empty
}

variable "grafana_password" {
  type      = string
  sensitive = true
  default   = ""   # Auto-generated if empty
}

variable "minio_root_user" {
  type      = string
  default   = ""   # Auto-generated if empty
}

variable "minio_root_password" {
  type      = string
  sensitive = true
  default   = ""   # Auto-generated if empty
}

# ── Platform ──────────────────────────────────────────────────────────────────
variable "github_pat" {
  type      = string
  sensitive = true
  default   = ""   # Must be real — no sensible random fallback
}

# ── Identity ──────────────────────────────────────────────────────────────────
variable "authentik_bootstrap_token" {
  description = "Authentik admin bootstrap token — auto-generated if empty"
  type        = string
  sensitive   = true
  default     = ""
}

variable "authentik_secret_key" {
  description = "Authentik Django secret key — auto-generated if empty"
  type        = string
  sensitive   = true
  default     = ""
}

variable "authentik_token" {
  type      = string
  sensitive = true
  default   = ""
}

