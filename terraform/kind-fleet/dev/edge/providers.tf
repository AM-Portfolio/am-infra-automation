locals {
  kubeconfig = pathexpand("~/.asrax/kubeconfig.am-dev-infra.yaml")
  env        = "dev"
  domain     = "asrax.in"
}

provider "kubernetes" {
  config_path    = local.kubeconfig
  config_context = "kind-am-dev-infra"
}

provider "helm" {
  kubernetes {
    config_path    = local.kubeconfig
    config_context = "kind-am-dev-infra"
  }
}

provider "kubectl" {
  config_path      = local.kubeconfig
  config_context   = "kind-am-dev-infra"
  load_config_file = true
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "cloudflare_account_id" {
  type      = string
  # Account id is not a secret; keep non-sensitive so manage_cloudflare can drive for_each.
  sensitive = false
  default   = ""
}

variable "tunnel_id" {
  type    = string
  default = "d652365f-bdb2-4382-a4e1-28b628bcf5d3"
}

variable "access_enforce" {
  description = "ZT-P1: enable Cloudflare Access apps. Keep false until OTP enroll (ZT-P0)."
  type        = bool
  default     = false
}

variable "enable_obs_access" {
  type    = bool
  default = true
}

variable "keycloak_issuer_url" {
  type    = string
  default = "https://auth-dev.asrax.in/realms/am-realm"
}

variable "keycloak_access_client_id" {
  type    = string
  default = "cloudflare-access"
}

variable "keycloak_access_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "break_glass_emails" {
  type    = list(string)
  default = []
}
