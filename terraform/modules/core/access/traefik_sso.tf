# ------------------------------------------------------------------------------
# Traefik Dashboard SSO — Forward Auth (Single Application)
# ------------------------------------------------------------------------------

# 1. Application Entity
resource "authentik_application" "traefik_dashboard" {
  name              = "Traefik Dashboard"
  slug              = "traefik-dashboard"
  protocol_provider = authentik_provider_proxy.traefik_proxy.id
  meta_icon         = "https://raw.githubusercontent.com/traefik/traefik/master/docs/content/assets/img/traefik.logo.png"
  group             = "Infrastructure"
}

# 2. Proxy Provider configured for Forward Auth
resource "authentik_provider_proxy" "traefik_proxy" {
  name               = "traefik-proxy"
  internal_host      = "http://mytraefik.internal" 
  external_host      = "https://${local.traefik_host}"
  mode               = "forward_single"
  authorization_flow = data.authentik_flow.implicit_consent.id
}
