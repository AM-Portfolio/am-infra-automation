locals {
  env                  = "dr"
  domain               = "asrax.in"
  # identity-infra-split Phase 6: platform tools on am-dr-infra (no third Kind).
  # Set false only for rollback to am-dr-platform :6445.
  co_locate_on_infra   = var.co_locate_on_infra
  gateway_same_cluster = local.co_locate_on_infra
  cross_cluster_routes = !local.co_locate_on_infra
  infra_kubeconfig     = "/data/am-state/kubeconfig.am-dr-infra.yaml"
  infra_context        = "kind-am-dr-infra"
  workload_kubeconfig  = local.co_locate_on_infra ? local.infra_kubeconfig : "/data/am-state/kubeconfig.am-dr-platform.yaml"
  workload_context     = local.co_locate_on_infra ? local.infra_context : "kind-am-dr-platform"
}

variable "co_locate_on_infra" {
  description = "When true, deploy platform tools+Keycloak on am-dr-infra; do not create am-dr-platform Kind. Default false until DR colocate soak."
  type        = bool
  default     = false
}

# Workload cluster (infra when co-located; legacy platform Kind otherwise).
provider "kubernetes" {
  config_path    = local.workload_kubeconfig
  config_context = local.workload_context
}

provider "helm" {
  kubernetes {
    config_path    = local.workload_kubeconfig
    config_context = local.workload_context
  }
}

provider "kubectl" {
  config_path      = local.workload_kubeconfig
  config_context   = local.workload_context
  load_config_file = true
}

# Infra Traefik / bridges / same-cluster routes use infra kubeconfig.
provider "kubernetes" {
  alias          = "infra"
  config_path    = local.infra_kubeconfig
  config_context = local.infra_context
}

provider "kubectl" {
  alias            = "infra"
  config_path      = local.infra_kubeconfig
  config_context   = local.infra_context
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
  description = "Docker IP of am-dr-platform-control-plane (legacy cross-cluster only)."
  type        = string
  default     = ""
}

variable "vault_addr" {
  type    = string
  default = "https://vault-dr.asrax.in"
}

variable "vault_token" {
  type      = string
  sensitive = true
  default   = ""
}
