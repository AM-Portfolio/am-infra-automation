# ------------------------------------------------------------------------------
# Default Flows and Certificates
# ------------------------------------------------------------------------------

data "authentik_flow" "default_auth_flow" {
  count = var.is_bootstrap ? 0 : 1
  slug  = "default-provider-authorization-explicit-consent"
}

data "authentik_certificate_key_pair" "default" {
  count = var.is_bootstrap ? 0 : 1
  name  = "authentik Default Setup"
}

data "authentik_flow" "default_invalidation_flow" {
  count = var.is_bootstrap ? 0 : 1
  slug  = "default-provider-invalidation-flow"
}

# ── Mapping OpenID Scopes ──────────────────────────────────────────────────────
data "authentik_property_mapping_provider_scope" "openid" {
  count = var.is_bootstrap ? 0 : 1
  name  = "authentik default OAuth Mapping: OpenID 'openid'"
}

data "authentik_property_mapping_provider_scope" "profile" {
  count = var.is_bootstrap ? 0 : 1
  name  = "authentik default OAuth Mapping: OpenID 'profile'"
}

data "authentik_property_mapping_provider_scope" "email" {
  count = var.is_bootstrap ? 0 : 1
  name  = "authentik default OAuth Mapping: OpenID 'email'"
}

output "auth_flow_id" {
  value = var.is_bootstrap ? "bootstrap-id" : data.authentik_flow.default_auth_flow[0].id
}

output "certificate_key_id" {
  value = var.is_bootstrap ? "bootstrap-id" : data.authentik_certificate_key_pair.default[0].id
}

output "invalidation_flow_id" {
  value = var.is_bootstrap ? "bootstrap-id" : data.authentik_flow.default_invalidation_flow[0].id
}

output "property_mappings" {
  value = var.is_bootstrap ? [] : [
    data.authentik_property_mapping_provider_scope.openid[0].id,
    data.authentik_property_mapping_provider_scope.profile[0].id,
    data.authentik_property_mapping_provider_scope.email[0].id
  ]
}
