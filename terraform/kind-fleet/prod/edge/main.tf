# Same Phase 2 Edge-first pattern as dev. Do not terraform apply this folder on the laptop.

locals {
  env    = "prod"
  domain = "asrax.in"
}

resource "terraform_data" "env_folder_guard" {
  input = local.env
  lifecycle {
    precondition {
      condition     = local.env == "prod"
      error_message = "kind-fleet/prod/edge must set local.env = \"prod\". Do not apply prod edge on the laptop."
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

provider "kubernetes" {
  config_path    = "/data/am-state/kubeconfig.am-prod-infra.yaml"
  config_context = "kind-am-prod-infra"
}

provider "helm" {
  kubernetes {
    config_path    = "/data/am-state/kubeconfig.am-prod-infra.yaml"
    config_context = "kind-am-prod-infra"
  }
}

provider "kubectl" {
  config_path      = "/data/am-state/kubeconfig.am-prod-infra.yaml"
  config_context   = "kind-am-prod-infra"
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
  # Prod uses bare product hosts (vault.asrax.in, …). Do NOT list grafana/loki/prometheus —
  # those are the shared obs hub (laptop interim → VPS2), owned by the Grafana host tunnel only.
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
    # Product UIs on apps Traefik (via apps-traefik-bridge on infra)
    "am",
    "corp",
    "asrax",
  ]
  bare_https_names = []
  # Apex company profile (same asrax-ui as asrax.asrax.in)
  extra_fqdns = ["asrax.in"]
}

output "traefik_origin" { value = module.edge.traefik_origin }
output "https_fqdn" { value = module.edge.https_fqdn }
