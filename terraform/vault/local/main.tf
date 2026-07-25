# ==============================================================================
# VAULT LAYER — Root Entrypoint (local)
#
# SMART SECRET RESOLUTION STRATEGY
# Priority order for every secret:
#   1. .env file value (injected via TF_VAR_* by manage.js)  → use as-is
#   2. auto-generated random_password                         → if .env is empty
#
# After this layer runs, ALL secrets live in environment-scoped Vault KV paths:
#   secret/<env>/infra/gateway    → cloudflare tokens
#   secret/<env>/infra/databases  → postgresql, mongodb, redis, influxdb, grafana
#   secret/<env>/infra/identity   → authentik bootstrap token
#   secret/<env>/infra/platform   → github_pat
#
# e.g for local:  secret/local/infra/gateway
# e.g for preprod: secret/preprod/infra/gateway
#
# Downstream layers read from Vault using:
#   data "vault_kv_secret_v2" { mount = "secret" name = "${var.environment}/infra/..." }
# ==============================================================================

# ── Step 1: Deploy Vault using the existing child module ──────────────────────
module "vault" {
  source           = "../../modules/apps/vault"
  root_domain      = var.root_domain
  environment      = var.environment
  namespace        = "vault"
  infra_namespace  = "infra"
  vault_unseal_key = var.vault_unseal_key
  kubeconfig_path  = var.kubeconfig_path
}

# ── Step 2: Auto-generate fallback secrets ────────────────────────────────────
# These always run, but locals.resolved below only picks them when .env is empty.
resource "random_password" "postgresql" {
  length  = 24
  special = false
}

resource "random_password" "mongodb" {
  length  = 24
  special = false
}

resource "random_password" "redis" {
  length  = 20
  special = false
}

resource "random_password" "influxdb_token" {
  length  = 40
  special = false
}

resource "random_password" "influxdb" {
  length  = 24
  special = false
}

resource "random_password" "grafana" {
  length  = 20
  special = false
}

resource "random_password" "grafana_oidc_client_secret" {
  length  = 32
  special = true
}

resource "random_password" "authentik_bootstrap" {
  length  = 32
  special = false
}

resource "random_password" "minio_root" {
  length  = 32
  special = false
}

resource "random_password" "authentik_secret_key" {
  length  = 50
  special = false
}

resource "random_password" "cloudflare_tunnel_secret" {
  length  = 32
  special = false
}

# ── Step 3: Resolve final values (.env wins; fallback to generated) ───────────
locals {
  resolved = {
    postgresql_password      = coalesce(var.postgresql_password,      random_password.postgresql.result)
    mongodb_password         = coalesce(var.mongodb_password,         random_password.mongodb.result)
    redis_password           = coalesce(var.redis_password,           random_password.redis.result)
    influxdb_token           = coalesce(var.influxdb_token,           random_password.influxdb_token.result)
    influxdb_password        = random_password.influxdb.result
    grafana_password         = coalesce(var.grafana_password,         random_password.grafana.result)
    grafana_oidc_client_secret = random_password.grafana_oidc_client_secret.result
    authentik_bootstrap      = coalesce(var.authentik_bootstrap_token, random_password.authentik_bootstrap.result)
    authentik_secret_key     = coalesce(var.authentik_secret_key,     random_password.authentik_secret_key.result)
    minio_root_user          = var.minio_root_user != "" ? var.minio_root_user : "minioadmin"
    minio_root_password      = coalesce(var.minio_root_password, random_password.minio_root.result)
    cloudflare_api_token     = var.cloudflare_api_token
    cloudflare_email         = var.cloudflare_email
    cloudflare_tunnel_token  = var.cloudflare_tunnel_token
    cloudflare_account_id    = var.cloudflare_account_id
    cloudflare_zone_id       = var.cloudflare_zone_id
    cloudflare_tunnel_secret = coalesce(var.cloudflare_tunnel_secret, random_password.cloudflare_tunnel_secret.result)
    github_pat               = var.github_pat                 # Must be real
  }
}

# ── Step 4: Mount the KV-V2 engine ───────────────────────────────────────────
resource "vault_mount" "secret" {
  path        = "secret"
  type        = "kv"
  options     = { version = "2" }
  description = "Primary KV-V2 store — source of truth for all AM infrastructure secrets"
  depends_on  = [module.vault]
}
# ── Step 3a: Vault Policy for automation (read OIDC creds, write token) �nresource "vault_policy" "am_automation" {
  name   = "am-automation-${var.environment}"
  policy = <<EOT
path "secret/data/${var.environment}/infra/authentik/automation" {
  capabilities = ["read"]
}

path "secret/data/${var.environment}/infra/identity/automation" {
  capabilities = ["create", "update", "read"]
}
EOT
}

# ── Step 3b: AppRole for automation scripts �nresource "vault_approle_auth_backend_role" "am_automation_role" {
  backend          = "approle"
  role_name        = "am-automation-${var.environment}"
  token_ttl        = 600
  token_max_ttl    = 1800
  token_policies   = [vault_policy.am_automation.name]
  bind_secret_id   = true
  secret_id_num_uses = 0
  secret_id_ttl    = "0"
}

# ── Step 3c: Generate Secret ID for automation AppRole �nresource "vault_approle_auth_backend_role_secret_id" "am_automation_secret_id" {
  backend   = "approle"
  role_name = vault_approle_auth_backend_role.am_automation_role.role_name
}


# End of automation role definition

# ── Step 5: Seed secrets into Vault KV paths (environment-scoped) ────────────
# All paths are prefixed with var.environment so local/preprod secrets never
# overwrite each other even if pointing at the same Vault instance.
resource "vault_kv_secret_v2" "gateway" {
  mount = vault_mount.secret.path
  name  = "${var.environment}/infra/gateway"
  data_json = jsonencode({
    cloudflare_api_token     = local.resolved.cloudflare_api_token
    cloudflare_email         = local.resolved.cloudflare_email
    cloudflare_tunnel_token  = local.resolved.cloudflare_tunnel_token
    cloudflare_account_id    = local.resolved.cloudflare_account_id
    cloudflare_zone_id       = local.resolved.cloudflare_zone_id
    cloudflare_tunnel_secret = local.resolved.cloudflare_tunnel_secret
  })
}

resource "vault_kv_secret_v2" "databases" {
  mount = vault_mount.secret.path
  name  = "${var.environment}/infra/databases"
  data_json = jsonencode({
    postgresql_password = local.resolved.postgresql_password
    mongodb_password    = local.resolved.mongodb_password
    redis_password      = local.resolved.redis_password
    influxdb_token              = local.resolved.influxdb_token
    influxdb_password           = local.resolved.influxdb_password
    grafana_password            = local.resolved.grafana_password
    grafana_oidc_client_secret  = local.resolved.grafana_oidc_client_secret
    minio_root_user     = local.resolved.minio_root_user
    minio_root_password = local.resolved.minio_root_password
  })
}

resource "vault_kv_secret_v2" "identity" {
  mount = vault_mount.secret.path
  name  = "${var.environment}/infra/identity"
  data_json = jsonencode({
    authentik_bootstrap_token = local.resolved.authentik_bootstrap,
    authentik_secret_key      = local.resolved.authentik_secret_key,
    authentik_client_id       = var.authentik_client_id,
    authentik_client_secret   = var.authentik_client_secret
  })
}

resource "vault_kv_secret_v2" "platform" {
  mount = vault_mount.secret.path
  name  = "${var.environment}/infra/platform"
  data_json = jsonencode({
    github_pat = local.resolved.github_pat
  })
}

resource "vault_kv_secret_v2" "admin" {
  mount = vault_mount.secret.path
  name  = "${var.environment}/infra/admin"
  data_json = jsonencode({
    headlamp_token = ""
  })
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "vault_address" {
  description = "Internal Kubernetes service address for downstream layers"
  value       = "http://vault.vault.svc.cluster.local:8200"
}

output "secret_resolution_summary" {
  description = "Shows whether each secret came from .env or was auto-generated"
  sensitive   = true
  value = {
    postgresql_from_env       = var.postgresql_password != ""
    mongodb_from_env          = var.mongodb_password != ""
    redis_from_env            = var.redis_password != ""
    influxdb_from_env         = var.influxdb_token != ""
    grafana_from_env          = var.grafana_password != ""
    authentik_from_env        = var.authentik_bootstrap_token != ""
    cloudflare_api_from_env    = var.cloudflare_api_token != ""
    cloudflare_tunnel_from_env = var.cloudflare_tunnel_token != ""
    github_pat_from_env        = var.github_pat != ""
    minio_root_from_env        = var.minio_root_password != ""
  }
}

output "am_automation_role_id" {
  description = "AppRole role_id for automation"
  value       = vault_approle_auth_backend_role.am_automation_role.role_id
}

output "am_automation_secret_id" {
  description = "AppRole secret_id for automation"
  value       = vault_approle_auth_backend_role_secret_id.am_automation_secret_id.secret_id
  sensitive   = true
}

