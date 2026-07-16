module "postgresql" {
  source           = "../modules/apps/postgresql"
  root_domain      = var.root_domain
  namespace        = var.namespace_infra
  db_password      = var.postgresql_password
  pgadmin_password = var.pgadmin_password
  environment      = var.environment
}
