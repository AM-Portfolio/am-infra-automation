# ------------------------------------------------------------------------------
# Vault SSO — OIDC (OAuth2) Configuration
# ------------------------------------------------------------------------------

# Using Default Implicit Consent flow for automatic SSO
# (data.authentik_flow.implicit_consent is defined in outposts.tf)

data "authentik_certificate_key_pair" "default" {
  name = "authentik Self-signed Certificate"
}

# 1. Application Entity
resource "authentik_application" "vault" {
  name              = "Vault OIDC"
  slug              = "vault-sso"
  protocol_provider = authentik_provider_oauth2.vault_oauth2.id
  meta_icon         = "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/svg/hashicorp-vault.svg"
  meta_launch_url   = "https://${local.vault_host}"
}

# 2. OAuth2 Provider
resource "authentik_provider_oauth2" "vault_oauth2" {
  name               = "vault-oauth2"
  client_id          = "vault_oidc_client"
  client_secret      = var.vault_oidc_client_secret 
  authorization_flow = data.authentik_flow.implicit_consent.id
  signing_key        = data.authentik_certificate_key_pair.default.id
  
  property_mappings = [
    "547c2009-5d7c-470a-9654-076c8244502c", # openid
    "a74ee01e-5ed3-49d6-950a-b42179e3131f", # email
    "f6e927c8-acc9-4a9b-bb3d-2fe9d0a779f9"  # profile
  ]
  
  redirect_uris = [
    "https://${local.vault_host}/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8200/ui/vault/auth/oidc/oidc/callback"
  ]
}







# ------------------------------------------------------------------------------
# Vault Local Config (Binding Authentik)
# ------------------------------------------------------------------------------

resource "vault_jwt_auth_backend" "oidc" {
  description        = "OIDC authentication via Authentik"
  path               = "oidc"
  type               = "oidc"
  oidc_discovery_url = "https://${local.authentik_host}/application/o/vault-sso/"
  oidc_client_id     = authentik_provider_oauth2.vault_oauth2.client_id
  oidc_client_secret = var.vault_oidc_client_secret
  default_role       = "default"
  
  tune {
    listing_visibility = "unauth" 
  }
}

resource "vault_jwt_auth_backend_role" "default" {
  backend        = vault_jwt_auth_backend.oidc.path
  role_name      = "default"
  token_policies = ["default"]
  
  bound_audiences = [authentik_provider_oauth2.vault_oauth2.client_id]
  user_claim      = "sub"
  claim_mappings = {
    name  = "name"
  }
  
  # This makes the user login with "default" role
  # Normally you map Authentik groups to Vault policies here or in a separate group alias setup.
  allowed_redirect_uris = [
    "https://${local.vault_host}/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8200/ui/vault/auth/oidc/oidc/callback"
  ]
}
