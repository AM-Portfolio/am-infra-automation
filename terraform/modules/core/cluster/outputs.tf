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
