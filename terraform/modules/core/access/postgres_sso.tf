# ------------------------------------------------------------------------------
# pgAdmin SSO — Native OIDC
# ------------------------------------------------------------------------------

resource "authentik_application" "pgadmin" {
  name              = "pgAdmin"
  slug              = "pgadmin"
  protocol_provider = authentik_provider_oauth2.pgadmin.id
  meta_icon         = "https://avatars.githubusercontent.com/u/177543?s=48&v=4"
  meta_launch_url   = "https://pgadmin${local.domain_suffix}.${var.root_domain}"
  group             = "Data Stores"
}
