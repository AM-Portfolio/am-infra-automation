output "environment" {
  value = var.environment
}

output "keycloak" { value = local.row.keycloak }
output "argocd_server" { value = local.row.argocd_server }
output "argocd_controller" { value = local.row.argocd_controller }
output "argocd_repo_server" { value = local.row.argocd_repo_server }
output "temporal_server" { value = local.row.temporal_server }
output "temporal_web" { value = local.row.temporal_web }
output "lago_api" { value = local.row.lago_api }
output "lago_front" { value = local.row.lago_front }
output "n8n" { value = local.row.n8n }
output "growthbook_frontend" { value = local.row.growthbook_frontend }
output "growthbook_backend" { value = local.row.growthbook_backend }
output "openproject" { value = local.row.openproject }
output "litellm" { value = local.row.litellm }
output "langfuse_web" { value = local.row.langfuse_web }
output "langfuse_clickhouse" { value = local.row.langfuse_clickhouse }
output "novu_api" { value = local.row.novu_api }
output "novu_worker" { value = local.row.novu_worker }
output "novu_web" { value = local.row.novu_web }
output "novu_ws" { value = local.row.novu_ws }
