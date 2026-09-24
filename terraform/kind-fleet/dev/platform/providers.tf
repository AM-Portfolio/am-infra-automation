locals {
  env    = "dev"
  domain = "asrax.in"
}

# Platform cluster (created by module.cluster in this stack).
provider "kubernetes" {
  host                   = module.cluster.endpoint
  client_certificate     = module.cluster.client_certificate
  client_key             = module.cluster.client_key
  cluster_ca_certificate = module.cluster.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = module.cluster.endpoint
    client_certificate     = module.cluster.client_certificate
    client_key             = module.cluster.client_key
    cluster_ca_certificate = module.cluster.cluster_ca_certificate
  }
}

provider "kubectl" {
  host                   = module.cluster.endpoint
  client_certificate     = module.cluster.client_certificate
  client_key             = module.cluster.client_key
  cluster_ca_certificate = module.cluster.cluster_ca_certificate
  load_config_file       = false
}

# Infra Traefik / bridges.
provider "kubernetes" {
  alias          = "infra"
  config_path    = pathexpand("~/.asrax/kubeconfig.am-dev-infra.yaml")
  config_context = "kind-am-dev-infra"
}

provider "kubectl" {
  alias            = "infra"
  config_path      = pathexpand("~/.asrax/kubeconfig.am-dev-infra.yaml")
  config_context   = "kind-am-dev-infra"
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
  description = "Docker IP of am-dev-platform-control-plane on the kind network."
  type        = string
  default     = ""
}

variable "vault_addr" {
  type    = string
  default = "https://vault-dev.asrax.in"
}

variable "vault_token" {
  type      = string
  sensitive = true
  default   = ""
}
