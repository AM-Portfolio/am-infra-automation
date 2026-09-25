locals {
  env              = "prod"
  domain           = "asrax.in"
  platform_kubeconfig = "/data/am-state/kubeconfig.am-prod-platform.yaml"
}

# Use rewritten kubeconfig (127.0.0.1:6445). module.cluster.endpoint is
# https://0.0.0.0:6445 which fails TLS SAN checks on VPS (api_server_address).
provider "kubernetes" {
  config_path    = local.platform_kubeconfig
  config_context = "kind-am-prod-platform"
}

provider "helm" {
  kubernetes {
    config_path    = local.platform_kubeconfig
    config_context = "kind-am-prod-platform"
  }
}

provider "kubectl" {
  config_path      = local.platform_kubeconfig
  config_context   = "kind-am-prod-platform"
  load_config_file = true
}

# Infra Traefik / bridges (VPS SoT kubeconfig).
provider "kubernetes" {
  alias          = "infra"
  config_path    = "/data/am-state/kubeconfig.am-prod-infra.yaml"
  config_context = "kind-am-prod-infra"
}

provider "kubectl" {
  alias            = "infra"
  config_path      = "/data/am-state/kubeconfig.am-prod-infra.yaml"
  config_context   = "kind-am-prod-infra"
  load_config_file = true
}

variable "keycloak_db_password" {
  type      = string
  sensitive = true
}

variable "temporal_db_password" {
  type      = string
  sensitive = true
}

variable "lago_db_password" {
  type      = string
  sensitive = true
}

variable "n8n_db_password" {
  type      = string
  sensitive = true
}

variable "openproject_db_password" {
  type      = string
  sensitive = true
}

variable "litellm_db_password" {
  type      = string
  sensitive = true
}

variable "langfuse_db_password" {
  type      = string
  sensitive = true
}

variable "growthbook_mongo_password" {
  type      = string
  sensitive = true
}

variable "langfuse_minio_password" {
  type      = string
  sensitive = true
}

variable "mongo_admin_password" {
  type      = string
  sensitive = true
}

variable "redis_password" {
  type      = string
  sensitive = true
}

variable "platform_node_ip" {
  description = "Docker IP of am-prod-platform-control-plane on the kind network."
  type        = string
  default     = ""
}

variable "vault_addr" {
  type    = string
  default = "https://vault.asrax.in"
}

variable "vault_token" {
  type      = string
  sensitive = true
  default   = ""
}
