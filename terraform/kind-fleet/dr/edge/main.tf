# Same Phase 2 Edge-first pattern as dev. Do not terraform apply this folder on the laptop.

locals {
  env    = "dr"
  domain = "asrax.in"
}

resource "terraform_data" "env_folder_guard" {
  input = local.env
  lifecycle {
    precondition {
      condition     = local.env == "dr"
      error_message = "kind-fleet/dr/edge must set local.env = \"dr\". Do not apply DR edge on the laptop."
    }
  }
}

variable "tunnel_id" {
  type    = string
  default = ""
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "cloudflare_account_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "kubeapi_kind_api_origin" {
  description = "Additive tunnel origin for kubeapi-dr.asrax.in (Kind am-dr-apps API). Empty = omit."
  type        = string
  default     = "https://127.0.0.1:6443"
}

variable "enable_kubeapi_ingress" {
  type    = bool
  default = true
}

provider "kubernetes" {
  config_path    = "/data/am-state/kubeconfig.am-dr-infra.yaml"
  config_context = "kind-am-dr-infra"
}

provider "helm" {
  kubernetes {
    config_path    = "/data/am-state/kubeconfig.am-dr-infra.yaml"
    config_context = "kind-am-dr-infra"
  }
}

provider "kubectl" {
  config_path      = "/data/am-state/kubeconfig.am-dr-infra.yaml"
  config_context   = "kind-am-dr-infra"
  load_config_file = true
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

module "edge" {
  source                = "../../../modules/core/edge"
  environment           = local.env
  root_domain           = local.domain
  namespace             = "infra"
  tunnel_id             = var.tunnel_id
  cloudflare_account_id = var.cloudflare_account_id
  # nonsensitive: boolean gate only — token/account stay sensitive on the provider
  manage_cloudflare     = nonsensitive(var.tunnel_id != "" && var.cloudflare_api_token != "" && var.cloudflare_account_id != "")
  # Do NOT list grafana/loki/prometheus — shared obs hub lives on the Grafana host tunnel only.
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
    "am",
    "corp",
    "asrax",
  ]
  bare_https_names = []
  # Bare prod FQDNs on tunnel only — DNS owned by prod/cloudflare-lb (DR primary / Contabo fallback).
  tunnel_only_fqdns = [
    "vault.asrax.in",
    "minio.asrax.in",
    "s3.asrax.in",
    "influx.asrax.in",
    "traefik.asrax.in",
    "pgadmin.asrax.in",
    "mongo-express.asrax.in",
    "kafka-ui.asrax.in",
    "redis-ui.asrax.in",
    "auth.asrax.in",
    "argocd.asrax.in",
    "temporal.asrax.in",
    "lago.asrax.in",
    "n8n.asrax.in",
    "growthbook.asrax.in",
    "openproject.asrax.in",
    "litellm.asrax.in",
    "langfuse.asrax.in",
    "novu.asrax.in",
    "am.asrax.in",
    "corp.asrax.in",
    "asrax.asrax.in",
    "asrax.in",
  ]
  # Additive Kind API hostname (DNS owned by kind-fleet/dr/argo-kubeapi).
  extra_origin_ingress = var.enable_kubeapi_ingress && var.kubeapi_kind_api_origin != "" ? {
    "kubeapi-dr.asrax.in" = var.kubeapi_kind_api_origin
  } : {}
}

output "traefik_origin" { value = module.edge.traefik_origin }
output "https_fqdn" { value = module.edge.https_fqdn }
