# ------------------------------------------------------------------------------
# SHARED RESOURCES — Flows & Outposts
# ------------------------------------------------------------------------------

data "authentik_flow" "implicit_consent" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_invalidation" {
  slug = "default-invalidation-flow"
}

# ------------------------------------------------------------------------------
# EMBEDDED OUTPOST — Centrally Managed Provider Binding
# ------------------------------------------------------------------------------

# We group all Forward-Auth Proxy Providers here. 
# Binding them to the embedded outpost ensures Traefik can serve them
# via the internal Traefik-Authentik middleware.
resource "authentik_outpost" "embedded" {
  name               = "authentik Embedded Outpost"
  type               = "proxy"
  protocol_providers = [
    authentik_provider_proxy.traefik_proxy.id,
    authentik_provider_proxy.rover_proxy.id,
    # pgAdmin, Kafka, and Headlamp relocated to OIDC (no proxy needed)
    authentik_provider_proxy.mongo_proxy.id,
    authentik_provider_proxy.influx_proxy.id,
    authentik_provider_proxy.redis_proxy.id
  ]
  
  config = jsonencode({
    authentik_host          = "https://${local.authentik_host}"
    authentik_host_insecure = true
  })
}
