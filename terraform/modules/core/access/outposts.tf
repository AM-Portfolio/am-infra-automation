# ------------------------------------------------------------------------------
# SHARED RESOURCES — Flows & Outposts
# ------------------------------------------------------------------------------

data "authentik_flow" "implicit_consent" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_invalidation" {
  slug = "default-invalidation-flow"
}

data "authentik_scope_mapping" "openid" {
  managed = "goauthentik.io/providers/oauth2/scope-openid"
}

data "authentik_scope_mapping" "email" {
  managed = "goauthentik.io/providers/oauth2/scope-email"
}

data "authentik_scope_mapping" "profile" {
  managed = "goauthentik.io/providers/oauth2/scope-profile"
}

locals {
  openid_scope_id  = coalesce(try(data.authentik_scope_mapping.openid.id, null), "eb661959-11d8-4a6a-9bbb-ba7cccadd862")
  email_scope_id   = coalesce(try(data.authentik_scope_mapping.email.id, null), "e7cde48d-5d48-434a-a1f3-023424b42560")
  profile_scope_id = coalesce(try(data.authentik_scope_mapping.profile.id, null), "4431a322-758c-478c-ae45-4939bd4c4174")
}

# ------------------------------------------------------------------------------
# EMBEDDED OUTPOST — Centrally Managed Provider Binding
# ------------------------------------------------------------------------------

# We group all Forward-Auth Proxy Providers here. 
# Binding them to the embedded outpost ensures Traefik can serve them
# via the internal Traefik-Authentik middleware.
resource "authentik_outpost" "embedded" {
  name               = "am-infra-proxy-outpost"
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
