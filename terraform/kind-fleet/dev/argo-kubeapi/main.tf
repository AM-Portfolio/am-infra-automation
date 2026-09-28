# Contabo Argo → laptop Kind API hostname (dig / nonprod-dr).
# Additive DNS + optional Argo secret server patch. Tunnel origin: set on kind-fleet/dev/edge.

terraform {
  required_version = ">= 1.5"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

locals {
  env                 = "dev"
  kubeapi_hostname    = "kubeapi-dev.asrax.in"
  kubeapi_server_url  = "https://kubeapi-dev.asrax.in"
  argo_cluster_secret = "cluster-am-dev-apps"
}

variable "tunnel_id" {
  type        = string
  default     = ""
  description = "asrax-dev tunnel ID (DNS CNAME target)."
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
  # Valid charset placeholder so terraform plan works without real creds; override for apply.
  default   = "plan_only_no_dns_00000000000000000000"
}

variable "cloudflare_account_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "manage_dns" {
  type    = bool
  default = true
}

variable "enable_argo_patch" {
  type        = bool
  default     = false
  description = "Set true only after Phase 0 DNS/API probes pass and Contabo Argo kubeconfig is set."
}

variable "argo_kubeconfig" {
  type    = string
  default = ""
}

variable "argo_kube_context" {
  type    = string
  default = ""
}

variable "kind_api_origin" {
  type        = string
  default     = "https://host.docker.internal:6444"
  description = "Origin for edge extra_origin_ingress (Kind apiserver as seen by cloudflared on dig host)."
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

module "kubeapi" {
  source = "../../../modules/ops/argo-kubeapi-patch"

  enabled                  = true
  root_domain              = "asrax.in"
  kubeapi_hostname         = local.kubeapi_hostname
  kubeapi_server_url       = local.kubeapi_server_url
  tunnel_id                = var.tunnel_id
  cloudflare_account_id    = var.cloudflare_account_id
  manage_dns               = var.manage_dns && var.tunnel_id != "" && !startswith(var.cloudflare_api_token, "plan_only")
  argo_cluster_secret_name = local.argo_cluster_secret
  enable_argo_patch        = var.enable_argo_patch
  argo_kubeconfig          = var.argo_kubeconfig
  argo_kube_context        = var.argo_kube_context
}

output "kubeapi_hostname" { value = module.kubeapi.kubeapi_hostname }
output "kubeapi_server_url" { value = module.kubeapi.kubeapi_server_url }
output "dns_fqdn" { value = module.kubeapi.dns_fqdn }
output "argo_patch_applied" { value = module.kubeapi.argo_patch_applied }

output "edge_extra_origin_ingress" {
  value = {
    (local.kubeapi_hostname) = var.kind_api_origin
  }
}
