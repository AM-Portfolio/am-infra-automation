# ------------------------------------------------------------------------------
# Headlamp UI SSO — Native OIDC (Direct Integration)
# ------------------------------------------------------------------------------

resource "random_password" "headlamp_client_secret" {
  length  = 32
  special = true
}

resource "authentik_provider_oauth2" "headlamp" {
  name          = "headlamp"
  client_id     = "headlamp"
  client_secret = random_password.headlamp_client_secret.result
  
  authorization_flow  = data.authentik_flow.default_provider_authorization_implicit_consent.id
  
  # Standard Authentik OIDC Scopes (UUIDs)
  property_mappings = [
    "547c2009-5d7c-470a-9654-076c8244502c", # openid
    "a74ee01e-5ed3-49d6-950a-b42179e3131f", # email
    "f6e927c8-acc9-4a9b-bb3d-2fe9d0a779f9"  # profile
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
