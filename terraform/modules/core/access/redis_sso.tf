# ------------------------------------------------------------------------------
# Redis Commander SSO — Forward Auth (Single Application)
# ------------------------------------------------------------------------------

resource "authentik_application" "redis" {
  name              = "Redis Commander"
  slug              = "redis-commander"
  protocol_provider = authentik_provider_proxy.redis_proxy.id
  meta_icon         = "https://avatars.githubusercontent.com/u/1529926?s=200&v=4"
  meta_launch_url   = "https://redis${local.domain_suffix}.${var.root_domain}"
  group             = "Data Stores"
}

resource "authentik_provider_proxy" "redis_proxy" {
  name               = "redis-proxy"
  internal_host      = "http://redis-commander.infra.svc.cluster.local:80"
  external_host      = "https://redis${local.domain_suffix}.${var.root_domain}"
  mode               = "forward_single"
  authorization_flow = data.authentik_flow.implicit_consent.id
  property_mappings  = [authentik_scope_mapping.redis_basic_auth.id]
}
