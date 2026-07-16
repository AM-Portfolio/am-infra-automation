module "minio_force" {
  source              = "../../modules/apps/minio"
  root_domain         = var.root_domain
  namespace           = "infra"
  environment         = var.environment
  minio_root_user     = var.minio_root_user
  minio_root_password = var.minio_root_password
  oidc_enabled        = true
}
