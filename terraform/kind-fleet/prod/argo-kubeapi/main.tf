# Contabo main Argo → Contabo Kind am-prod-apps API hostname.

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
  kubeapi_hostname    = "kubeapi-prod.asrax.in"
  kubeapi_server_url  = "https://kubeapi-prod.asrax.in"
  argo_cluster_secret = "cluster-am-prod-apps"
}

variable "tunnel_id" {
  type        = string
  default     = ""
  description = "asrax-prod tunnel ID."
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
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
  type    = bool
  default = false
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
  default     = "https://127.0.0.1:6443"
  description = "Kind am-prod-apps apiserver as seen by Contabo cloudflared."
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
  value = { (local.kubeapi_hostname) = var.kind_api_origin }
}
