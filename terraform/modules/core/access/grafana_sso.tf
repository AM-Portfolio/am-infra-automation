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
  
  # Standard Authentik OIDC Scopes (UUIDs)
  property_mappings = [
    "547c2009-5d7c-470a-9654-076c8244502c", # openid
    "a74ee01e-5ed3-49d6-950a-b42179e3131f", # email
    "f6e927c8-acc9-4a9b-bb3d-2fe9d0a779f9"  # profile
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
