# ------------------------------------------------------------------------------
# Grafana SSO — Native OIDC (Direct Integration)
# ------------------------------------------------------------------------------

# Secret is now centrally managed in Vault
data "vault_kv_secret_v2" "databases" {
  mount = "secret"
  name  = "${var.environment}/infra/databases"
}

resource "authentik_provider_oauth2" "grafana" {
  name          = "grafana"
  client_id     = "grafana"
  client_secret = data.vault_kv_secret_v2.databases.data["grafana_oidc_client_secret"]
  
  authorization_flow  = data.authentik_flow.default_provider_authorization_implicit_consent.id
  
  property_mappings = [
    local.openid_scope_id,
    local.email_scope_id,
    local.profile_scope_id
  ]

  redirect_uris = [
    "https://grafana${local.domain_suffix}.${var.root_domain}/login/generic_oauth"
  ]
}

resource "authentik_application" "grafana" {
  name              = "Grafana"
  slug              = "grafana"
  protocol_provider = authentik_provider_oauth2.grafana.id
  meta_icon         = "https://raw.githubusercontent.com/grafana/grafana/main/public/img/grafana_icon.svg"
  
  group = "Monitoring"
}
