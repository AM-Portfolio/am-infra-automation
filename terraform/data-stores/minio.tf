# ------------------------------------------------------------------------------
# MinIO Object Storage
# ------------------------------------------------------------------------------

module "minio" {
  source              = "../modules/apps/minio"
  root_domain         = var.root_domain
  namespace           = var.namespace_infra
  environment         = var.environment
  minio_root_user     = var.minio_root_user
  minio_root_password = var.minio_root_password

  # OIDC Configuration (Enabled after first boot verification)
  oidc_enabled        = true 
}
