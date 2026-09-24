# Fleet Kind entrypoint. Do not apply terraform/foundation/{local,preprod}.
# Computed Kind name: am-dr-platform
# Host state (terraform init -backend-config=backend.hcl): /data/am-state/terraform/dr/platform/terraform.tfstate
# Phase 1: validate only. Do not terraform apply or kind create.

module "cluster" {
  source       = "../../../modules/core/cluster"
  env          = "dr"
  cluster_role = "platform"
}

output "cluster_name" {
  value = module.cluster.cluster_name
}

output "api_server_port" {
  value = module.cluster.api_server_port
}

output "node_shape" {
  value = module.cluster.node_shape
}

output "env" {
  value = module.cluster.env
}

output "cluster_role" {
  value = module.cluster.cluster_role
}