# Phase 2 edge. Apply on laptop after kind create, before or as retrofit of stores.
# Token secret cloudflare-tunnel/token is created outside git.

resource "terraform_data" "env_folder_guard" {
  input = local.env
  lifecycle {
    precondition {
      condition     = local.env == "dev"
      error_message = "kind-fleet/dev/edge must set local.env = \"dev\"."
    }
  }
}

module "edge" {
  source                = "../../../modules/core/edge"
  environment           = local.env
  root_domain           = local.domain
  namespace             = "infra"
  tunnel_id             = var.tunnel_id
  cloudflare_account_id = var.cloudflare_account_id
  # nonsensitive: boolean gate only — token/account stay sensitive on the provider
  manage_cloudflare     = nonsensitive(var.cloudflare_api_token != "" && var.cloudflare_account_id != "")
  https_names = [
    "vault",
    "minio",
    "s3",
    "influx",
    "traefik",
    "pgadmin",
    "mongo-express",
    "kafka-ui",
    "redis-ui",
    "auth",
    "argocd",
    "temporal",
    "lago",
    "n8n",
    "growthbook",
    "openproject",
    "litellm",
    "langfuse",
    "novu",
    "grafana",
    "loki",
    "prometheus",
  ]
  # Shared obs hub — no -dev suffix (prod/DR/preprod also push here later)
  bare_https_names = [
    "grafana",
    "loki",
    "prometheus",
  ]
}

# Zero-trust Access + data-plane CIDR list. access_enforce=false until ZT-P1 (enroll first).
module "zero_trust_access" {
  source = "../../../modules/core/zero-trust-access"
  count  = nonsensitive(var.cloudflare_api_token != "" && var.cloudflare_account_id != "") ? 1 : 0

  account_id              = var.cloudflare_account_id
  zone_id                 = data.cloudflare_zone.asrax[0].id
  root_domain             = local.domain
  environment             = local.env
  access_enforce          = var.access_enforce
  enable_obs_access       = var.enable_obs_access
  keycloak_issuer_url     = var.keycloak_issuer_url
  keycloak_client_id      = var.keycloak_access_client_id
  keycloak_client_secret  = var.keycloak_access_client_secret
  break_glass_emails      = var.break_glass_emails
  registry_path           = "${path.module}/../../access-allowlist/registry.json"
  product_ui_host         = "am-dev.asrax.in"
}

data "cloudflare_zone" "asrax" {
  count = nonsensitive(var.cloudflare_api_token != "" && var.cloudflare_account_id != "") ? 1 : 0
  name  = local.domain
}

module "data_plane_ip_allowlist" {
  source = "../../../modules/core/data-plane-ip-allowlist"

  registry_path      = "${path.module}/../../access-allowlist/registry.json"
  output_script_path = "${path.module}/../../access-allowlist/generated-allowlist.ps1"
}

output "traefik_origin" { value = module.edge.traefik_origin }
output "https_fqdn" { value = module.edge.https_fqdn }
output "zero_trust_access_enforce" {
  value = try(module.zero_trust_access[0].access_enforce, false)
}
output "alloy_access_client_id" {
  value     = try(module.zero_trust_access[0].service_token_client_id, "")
  sensitive = true
}
output "alloy_access_client_secret" {
  value     = try(module.zero_trust_access[0].service_token_client_secret, "")
  sensitive = true
}
output "data_plane_allowed_cidrs" {
  value = module.data_plane_ip_allowlist.allowed_cidrs
}
