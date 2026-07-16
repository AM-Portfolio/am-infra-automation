# ------------------------------------------------------------------------------
# OIDC Providers — Native SSO for Data Stores
# ------------------------------------------------------------------------------

data "authentik_flow" "default_auth" {
  slug = "default-authentication-flow"
}

data "authentik_flow" "default_provider_authorization_implicit_consent" {
  slug = "default-provider-authorization-implicit-consent"
}

# 🛠️ OAuth2/OIDC — pgAdmin 4
# ------------------------------------------------------------------------------
resource "random_password" "pgadmin_client_secret" {
  length  = 32
  special = true
}

resource "authentik_provider_oauth2" "pgadmin" {
  name          = "pgadmin"
  client_id     = "pgadmin"
  client_secret = random_password.pgadmin_client_secret.result
  
  authorization_flow  = data.authentik_flow.default_provider_authorization_implicit_consent.id
  
  redirect_uris = [
    "https://pgadmin${local.domain_suffix}.${var.root_domain}/oauth2/authorize"
  ]
}

# 🛠️ OAuth2/OIDC — Kafka UI
# ------------------------------------------------------------------------------
resource "random_password" "kafka_client_secret" {
  length  = 32
  special = true
}

resource "authentik_provider_oauth2" "kafka" {
  name          = "kafka-ui"
  client_id     = "kafka-ui"
  client_secret = random_password.kafka_client_secret.result
  
  authorization_flow  = data.authentik_flow.default_provider_authorization_implicit_consent.id
  
  redirect_uris = [
    "https://kafka${local.domain_suffix}.${var.root_domain}/login/oauth2/code/authentik"
  ]
}

# 💾 Vault Secret Storage — For the App layer to consume
# ------------------------------------------------------------------------------
resource "vault_generic_secret" "oidc_secrets" {
  path = "secret/infra/oidc-data-stores"
  data_json = jsonencode({
    # Monitoring
    grafana_client_id      = "grafana"
    grafana_client_secret  = data.vault_kv_secret_v2.databases.data["grafana_oidc_client_secret"]
    headlamp_client_id     = "headlamp"
    headlamp_client_secret = random_password.headlamp_client_secret.result
    
    # Data Stores
    pgadmin_client_id      = "pgadmin"
    pgadmin_client_secret  = random_password.pgadmin_client_secret.result
    kafka_client_id        = "kafka-ui"
    kafka_client_secret    = random_password.kafka_client_secret.result

    # Discovery
    oidc_issuer_url        = "https://authentik${local.domain_suffix}.${var.root_domain}/application/o"
  })
}
