output "auth_path" {
  value = vault_auth_backend.kubernetes_apps.path
}

output "role_name" {
  value = vault_kubernetes_auth_backend_role.am_backend.role_name
}

output "policy_name" {
  value = vault_policy.am_apps_read.name
}

output "bound_namespaces" {
  value = local.bound_namespaces
}

output "pull_secrets_created" {
  value = keys(kubernetes_secret_v1.ghcr)
}
