# ------------------------------------------------------------------------------
# Headlamp UI SSO — Native OIDC (Direct Integration)
# ------------------------------------------------------------------------------

resource "random_password" "headlamp_client_secret" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "authentik_provider_oauth2" "headlamp" {
  name          = "headlamp"
  client_id     = "headlamp"
  client_secret = random_password.headlamp_client_secret.result
  
  authorization_flow  = data.authentik_flow.default_provider_authorization_implicit_consent.id
  
  property_mappings = [
    local.openid_scope_id,
    local.email_scope_id,
    local.profile_scope_id
  ]

  redirect_uris = [
    "https://headlamp${local.domain_suffix}.${var.root_domain}/oidc-callback"
  ]
}

resource "authentik_application" "headlamp" {
  name              = "Headlamp UI"
  slug              = "headlamp-ui"
  protocol_provider = authentik_provider_oauth2.headlamp.id
  meta_icon         = "https://raw.githubusercontent.com/kinvolk/headlamp/main/frontend/public/favicon.ico"
  
  group = "Monitoring"
}
