output "cluster_name" {
  value       = local.cluster_name
  description = "Computed Kind name: am-<env>-<role> or am-obs."
}

output "env" {
  value       = var.env
  description = "Business env token."
}

output "cluster_role" {
  value       = var.cluster_role
  description = "Fleet role."
}

output "api_server_port" {
  value       = local.api_server_port
  description = "Kind API port."
}

output "node_shape" {
  value       = local.node_shape
  description = "one or two nodes."
}

output "fleet_kind_names" {
  value       = local.fleet_kind_names
  description = "Always three for business envs: am-<env>-{infra,apps,platform}. obs → [am-obs]."
}

output "endpoint" {
  value       = kind_cluster.this.endpoint
  description = "The endpoint of the KinD cluster API server."
}

output "client_certificate" {
  value       = kind_cluster.this.client_certificate
  description = "The client certificate for authenticating to the cluster."
  sensitive   = true
}

output "client_key" {
  value       = kind_cluster.this.client_key
  description = "The client key for authenticating to the cluster."
  sensitive   = true
}

output "cluster_ca_certificate" {
  value       = kind_cluster.this.cluster_ca_certificate
  description = "The CA certificate for the cluster."
  sensitive   = true
}
