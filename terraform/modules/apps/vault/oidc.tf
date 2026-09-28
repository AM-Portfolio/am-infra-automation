# Keycloak OIDC for Vault UI humans (iam-sso Phase 2). CSI / AppRole for pods unchanged.

variable "oidc_enabled" {
  type        = bool
  default     = false
  description = "Enable Vault auth method oidc → Keycloak am-realm."
}

variable "oidc_discovery_url" {
  type        = string
  default     = ""
  description = "Keycloak issuer, e.g. https://auth.asrax.in/realms/am-realm"
}

variable "oidc_client_id" {
  type    = string
  default = "vault-ui"
}

variable "oidc_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "oidc_redirect_uris" {
  type    = list(string)
  default = []
}

locals {
  vault_ui_host = var.environment == "prod" ? "vault.${var.root_domain}" : "vault-${var.environment}.${var.root_domain}"
  oidc_redirects = length(var.oidc_redirect_uris) > 0 ? var.oidc_redirect_uris : [
    "https://${local.vault_ui_host}/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8200/ui/vault/auth/oidc/oidc/callback",
  ]
}

resource "vault_jwt_auth_backend" "oidc" {
  count              = var.oidc_enabled && var.oidc_discovery_url != "" && var.oidc_client_secret != "" ? 1 : 0
  description        = "OIDC via Keycloak am-realm (iam-sso)"
  path               = "oidc"
  type               = "oidc"
  oidc_discovery_url = var.oidc_discovery_url
  oidc_client_id     = var.oidc_client_id
  oidc_client_secret = var.oidc_client_secret
  # Vault UI often omits default_role from unauth mounts — operators type this Role name.
  default_role       = "am-admin"
  tune {
    listing_visibility = "unauth"
    default_lease_ttl  = "768h"
    max_lease_ttl      = "768h"
  }
}

resource "vault_policy" "am_admin" {
  count  = length(vault_jwt_auth_backend.oidc) > 0 ? 1 : 0
  name   = "am-sso-admin"
  policy = <<-EOT
    path "*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
  EOT
}

resource "vault_policy" "am_ops" {
  count  = length(vault_jwt_auth_backend.oidc) > 0 ? 1 : 0
  name   = "am-sso-ops"
  policy = <<-EOT
    path "apps/data/*" {
      capabilities = ["read", "list"]
    }
    path "secret/data/*" {
      capabilities = ["read", "list"]
    }
    path "sys/policies/*" {
      capabilities = ["read", "list"]
    }
  EOT
}

resource "vault_policy" "am_viewer" {
  count  = length(vault_jwt_auth_backend.oidc) > 0 ? 1 : 0
  name   = "am-sso-viewer"
  policy = <<-EOT
    path "apps/data/*" {
      capabilities = ["read", "list"]
    }
  EOT
}

resource "vault_jwt_auth_backend_role" "am_admin" {
  count                 = length(vault_jwt_auth_backend.oidc) > 0 ? 1 : 0
  backend               = vault_jwt_auth_backend.oidc[0].path
  role_name             = "am-admin"
  role_type             = "oidc"
  token_policies        = [vault_policy.am_admin[0].name]
  bound_audiences       = [var.oidc_client_id]
  user_claim            = "email"
  groups_claim          = "groups"
  bound_claims          = { groups = "am-admin" }
  bound_claims_type     = "string"
  allowed_redirect_uris = local.oidc_redirects
  oidc_scopes           = ["openid", "profile", "email", "roles", "groups"]
  verbose_oidc_logging  = false
}

resource "vault_jwt_auth_backend_role" "am_ops" {
  count                 = length(vault_jwt_auth_backend.oidc) > 0 ? 1 : 0
  backend               = vault_jwt_auth_backend.oidc[0].path
  role_name             = "am-ops"
  role_type             = "oidc"
  token_policies        = [vault_policy.am_ops[0].name]
  bound_audiences       = [var.oidc_client_id]
  user_claim            = "email"
  groups_claim          = "groups"
  bound_claims          = { groups = "am-ops" }
  bound_claims_type     = "string"
  allowed_redirect_uris = local.oidc_redirects
  oidc_scopes           = ["openid", "profile", "email", "roles", "groups"]
}

resource "vault_jwt_auth_backend_role" "am_viewer" {
  count                 = length(vault_jwt_auth_backend.oidc) > 0 ? 1 : 0
  backend               = vault_jwt_auth_backend.oidc[0].path
  role_name             = "am-viewer"
  role_type             = "oidc"
  token_policies        = [vault_policy.am_viewer[0].name]
  bound_audiences       = [var.oidc_client_id]
  user_claim            = "email"
  groups_claim          = "groups"
  bound_claims          = { groups = "am-viewer" }
  bound_claims_type     = "string"
  allowed_redirect_uris = local.oidc_redirects
  oidc_scopes           = ["openid", "profile", "email", "roles", "groups"]
}
