output "kubeconfig" {
  value     = module.cluster.kubeconfig
  sensitive = true
}

output "credentials" {
  value     = module.bootstrap.credentials
  sensitive = true
}

# --- Dynamic Kubeconfig Credentials (Zero-File Security Bridge) ---
output "kube_endpoint" {
  value = module.cluster.endpoint
}

output "kube_ca_cert" {
  value = module.cluster.cluster_ca_certificate
}

output "kube_client_cert" {
  value = module.cluster.client_certificate
}

output "kube_client_key" {
  value = module.cluster.client_key
}

output "infra_ns" {
  value = module.namespaces_core.infra_ns
}

output "identity_ns" {
  value = module.namespaces_core.identity_ns
}

output "monitoring_ns" {
  value = module.namespaces_core.monitoring_ns
}

output "vault_ns" {
  value = module.namespaces_core.vault_ns
}
