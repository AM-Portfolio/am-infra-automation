# Cloudflare Zero Trust Access — multi-app policies for AM fleet.
# auth-dev is NEVER an Access application (IdP chicken-and-egg).
# access_enforce=false → apps/policies not created (ZT-P0 enroll).
# When enable_obs_access + access_enforce: Service Token + Alloy headers REQUIRED.

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 4.40"
    }
  }
}

variable "account_id" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "root_domain" {
  type    = string
  default = "asrax.in"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "access_enforce" {
  description = "When false, create no Access applications (Phase ZT-P0)."
  type        = bool
  default     = false
}

variable "enable_obs_access" {
  description = "Put grafana/loki/prometheus behind Access (requires Service Token wiring)."
  type        = bool
  default     = true
}

variable "keycloak_issuer_url" {
  description = "e.g. https://auth-dev.asrax.in/realms/am-realm"
  type        = string
}

variable "keycloak_client_id" {
  type    = string
  default = "cloudflare-access"
}

variable "keycloak_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "break_glass_emails" {
  type    = list(string)
  default = []
}

variable "registry_path" {
  description = "Path to access-allowlist/registry.json"
  type        = string
}

variable "alloy_cf_access_client_id" {
  description = "Must be set (non-empty) when access_enforce && enable_obs_access — usually from Service Token output wired to Alloy."
  type        = string
  default     = ""
  sensitive   = true
}

variable "product_ui_host" {
  type    = string
  default = ""
}

variable "api_path_bypass_prefixes" {
  type = list(string)
  default = [
    "/gateway", "/identity", "/market", "/portfolio", "/trade",
    "/analysis", "/doc", "/parser", "/qa", "/corp", "/asrax",
    "/notification", "/subscription", "/user-platform",
  ]
}

locals {
  domain_suffix = var.environment == "prod" ? "" : "-${var.environment}"
  product_host  = var.product_ui_host != "" ? var.product_ui_host : "am${local.domain_suffix}.${var.root_domain}"

  registry = jsondecode(file(var.registry_path))
  entries  = try(local.registry.entries, [])

  cidrs_for = {
    for app in ["product-ui", "obs", "platform-ops", "platform-tools", "store-uis", "data-plane"] :
    app => distinct(flatten([
      for e in local.entries : contains(try(e.apps, []), app) ? [e.cidr] : []
    ]))
  }

  apps = {
    product-ui = {
      name   = "am-product-ui-${var.environment}"
      hosts  = [local.product_host]
      roles  = ["user", "viewer", "ops", "admin", "super_admin", "am-user", "am-viewer", "am-ops", "am-admin"]
      ip_key = "product-ui"
    }
    obs = {
      name   = "am-obs-${var.environment}"
      hosts  = ["grafana.${var.root_domain}", "loki.${var.root_domain}", "prometheus.${var.root_domain}"]
      roles  = ["ops", "admin", "super_admin", "am-ops", "am-admin"]
      ip_key = "obs"
    }
    platform-ops = {
      name = "am-platform-ops-${var.environment}"
      hosts = compact([
        "argocd${local.domain_suffix}.${var.root_domain}",
        "vault${local.domain_suffix}.${var.root_domain}",
        "temporal${local.domain_suffix}.${var.root_domain}",
        "traefik${local.domain_suffix}.${var.root_domain}",
      ])
      roles  = ["ops", "admin", "super_admin", "am-ops", "am-admin"]
      ip_key = "platform-ops"
    }
    platform-tools = {
      name = "am-platform-tools-${var.environment}"
      hosts = [
        for n in ["n8n", "openproject", "lago", "growthbook", "litellm", "langfuse", "novu"] :
        "${n}${local.domain_suffix}.${var.root_domain}"
      ]
      roles  = ["ops", "admin", "super_admin", "am-ops", "am-admin"]
      ip_key = "platform-tools"
    }
    store-uis = {
      name = "am-store-uis-${var.environment}"
      hosts = [
        for n in ["pgadmin", "mongo-express", "redis-ui", "kafka-ui", "minio", "influx"] :
        "${n}${local.domain_suffix}.${var.root_domain}"
      ]
      roles  = ["ops", "admin", "super_admin", "am-ops", "am-admin"]
      ip_key = "store-uis"
    }
  }

  apps_effective = var.enable_obs_access ? local.apps : {
    for k, v in local.apps : k => v if k != "obs"
  }

  create = var.access_enforce

  obs_needs_token = var.access_enforce && var.enable_obs_access
}

resource "terraform_data" "obs_alloy_guard" {
  input = local.obs_needs_token
  lifecycle {
    precondition {
      condition     = !local.obs_needs_token || local.create
      error_message = "enable_obs_access requires access_enforce=true so this module can create the Alloy Access Service Token in the same apply."
    }
  }
}

resource "cloudflare_zero_trust_access_identity_provider" "keycloak" {
  count = local.create ? 1 : 0

  account_id = var.account_id
  name       = "keycloak-am-realm-${var.environment}"
  type       = "oidc"
  config {
    client_id     = var.keycloak_client_id
    client_secret = var.keycloak_client_secret
    auth_url      = "${trimsuffix(var.keycloak_issuer_url, "/")}/protocol/openid-connect/auth"
    token_url     = "${trimsuffix(var.keycloak_issuer_url, "/")}/protocol/openid-connect/token"
    certs_url     = "${trimsuffix(var.keycloak_issuer_url, "/")}/protocol/openid-connect/certs"
  }
}

resource "cloudflare_zero_trust_access_service_token" "alloy" {
  count = local.create && var.enable_obs_access ? 1 : 0

  account_id = var.account_id
  name       = "alloy-obs-${var.environment}"
}

resource "cloudflare_zero_trust_access_application" "app" {
  for_each = local.create ? local.apps_effective : {}

  account_id                = var.account_id
  name                      = each.value.name
  domain                    = each.value.hosts[0]
  type                      = "self_hosted"
  session_duration          = "8h"
  auto_redirect_to_identity = true
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.keycloak[0].id]
}

resource "cloudflare_zero_trust_access_policy" "allow_roles" {
  for_each = local.create ? local.apps_effective : {}

  account_id     = var.account_id
  application_id = cloudflare_zero_trust_access_application.app[each.key].id
  name           = "${each.key}-roles"
  decision       = "allow"
  precedence     = 1

  include {
    # OIDC group/role claim — Cloudflare maps IdP groups; also allow email domain as fallback gate
    everyone = each.key == "product-ui" ? true : false
  }

  dynamic "include" {
    for_each = each.key == "product-ui" ? [] : [1]
    content {
      email_domain = [var.root_domain]
    }
  }

  dynamic "require" {
    for_each = length(local.cidrs_for[each.value.ip_key]) > 0 || each.key == "store-uis" ? [1] : []
    content {
      ip = length(local.cidrs_for[each.value.ip_key]) > 0 ? local.cidrs_for[each.value.ip_key] : ["127.0.0.1/32"]
    }
  }
}

resource "cloudflare_zero_trust_access_policy" "break_glass" {
  count = local.create && length(var.break_glass_emails) > 0 ? 1 : 0

  account_id     = var.account_id
  application_id = cloudflare_zero_trust_access_application.app["platform-ops"].id
  name           = "break-glass-email-pin"
  decision       = "allow"
  precedence     = 10

  include {
    email = var.break_glass_emails
  }
}

resource "cloudflare_zero_trust_access_policy" "alloy_service" {
  count = local.create && var.enable_obs_access ? 1 : 0

  account_id     = var.account_id
  application_id = cloudflare_zero_trust_access_application.app["obs"].id
  name           = "alloy-service-token"
  decision       = "non_identity"
  precedence     = 2

  include {
    service_token = [cloudflare_zero_trust_access_service_token.alloy[0].id]
  }
}

output "access_enforce" {
  value = var.access_enforce
}

output "service_token_client_id" {
  value     = try(cloudflare_zero_trust_access_service_token.alloy[0].client_id, "")
  sensitive = true
}

output "service_token_client_secret" {
  value     = try(cloudflare_zero_trust_access_service_token.alloy[0].client_secret, "")
  sensitive = true
}

output "data_plane_cidrs" {
  value = distinct(concat(
    ["172.19.0.0/16", "10.77.1.0/24"],
    local.cidrs_for["data-plane"],
  ))
}

output "cidrs_by_app" {
  value = local.cidrs_for
}

output "identity_provider_id" {
  value = try(cloudflare_zero_trust_access_identity_provider.keycloak[0].id, "")
}
