# OBSOLETE for Phase 11 SoT — VPS2 obs is Docker Compose (no Kind).
# See: compose/obs/ + docs/kind-fleet-clusters/OBS_DEPLOY.md
# Do not terraform apply or kind create on VPS2 for the shared Grafana/Loki hub.
# Fleet Kind entrypoint stub only (am-obs name). Do not apply terraform/foundation/{local,preprod}.
# Host state path (unused for Compose hub): /data/am-state/terraform/obs/terraform.tfstate

module "cluster" {
  source       = "../../modules/core/cluster"
  env          = "obs"
  cluster_role = "obs"
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