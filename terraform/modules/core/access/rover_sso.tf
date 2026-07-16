# ------------------------------------------------------------------------------
# Rover UI SSO — Forward Auth (Proxy Integration)
# ------------------------------------------------------------------------------

# 1. Application Entity
resource "authentik_application" "rover" {
  name              = "Rover UI"
  slug              = "rover-ui"
  protocol_provider = authentik_provider_proxy.rover_proxy.id
  meta_icon         = "https://raw.githubusercontent.com/im2nguyen/rover/main/ui/public/favicon.ico"
  group             = "Infrastructure"
}

# 2. Proxy Provider configured for Forward Auth
resource "authentik_provider_proxy" "rover_proxy" {
  name               = "rover-proxy"
  # Internal host is the Kubernetes service name in the infra namespace
  internal_host      = "http://rover.infra.svc.cluster.local:9000"
  external_host      = "https://rover${local.domain_suffix}.${var.root_domain}"
  mode               = "forward_single"
  authorization_flow = data.authentik_flow.implicit_consent.id
}
