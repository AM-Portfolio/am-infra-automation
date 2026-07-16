# ------------------------------------------------------------------------------
# Mongo Express SSO — Forward Auth (Single Application)
# ------------------------------------------------------------------------------

resource "authentik_application" "mongo" {
  name              = "Mongo Express"
  slug              = "mongo-express"
  protocol_provider = authentik_provider_proxy.mongo_proxy.id
  meta_icon         = "https://github.com/mongodb/mongo/blob/master/docs/leaf.svg"
  meta_launch_url   = "https://mongo${local.domain_suffix}.${var.root_domain}"
  group             = "Data Stores"
}


resource "authentik_provider_proxy" "mongo_proxy" {
  name               = "mongo-proxy"
  internal_host      = "http://mongo-express.infra.svc.cluster.local:8081"
  external_host      = "https://mongo${local.domain_suffix}.${var.root_domain}"
  mode               = "forward_single"
  authorization_flow = data.authentik_flow.implicit_consent.id
  property_mappings  = [authentik_scope_mapping.mongo_basic_auth.id]
}
