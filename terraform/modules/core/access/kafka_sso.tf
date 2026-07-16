# ------------------------------------------------------------------------------
# Kafka UI SSO — Native OIDC
# ------------------------------------------------------------------------------

resource "authentik_application" "kafka" {
  name              = "Kafka UI"
  slug              = "kafka-ui"
  protocol_provider = authentik_provider_oauth2.kafka.id
  meta_icon         = "https://avatars.githubusercontent.com/u/47359?s=48&v=4"
  meta_launch_url   = "https://kafka${local.domain_suffix}.${var.root_domain}"
  group             = "Data Stores"
}
