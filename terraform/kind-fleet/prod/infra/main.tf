# Fleet Kind entrypoint. Do not apply terraform/foundation/{local,preprod}.
# Computed Kind name: am-prod-infra
# Host state (terraform init -backend-config=backend.hcl): /data/am-state/terraform/prod/infra/terraform.tfstate
# Serve-first (64 GB): node_shape defaults to two for prod infra.

module "cluster" {
  source       = "../../../modules/core/cluster"
  env          = "prod"
  cluster_role = "infra"
  # node_shape omitted → two (control-plane + worker) on 8c/64GB
  vps_ram_gb           = 64
  api_server_address   = "0.0.0.0"
  vps_ip               = "203.174.22.129"
  config_output_path   = "/data/am-state/kubeconfig.am-prod-infra.yaml"
  enable_data_mount    = true
  data_host_path       = "/data/am-infra"
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

output "fleet_kind_names" {
  value = module.cluster.fleet_kind_names
}

output "env" {
  value = module.cluster.env
}

output "cluster_role" {
  value = module.cluster.cluster_role
}
