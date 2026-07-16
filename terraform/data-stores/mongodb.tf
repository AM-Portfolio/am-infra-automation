module "mongodb" {
  source              = "../modules/apps/mongodb"
  root_domain         = var.root_domain
  namespace           = var.namespace_infra
  mongo_root_password = var.mongodb_password
  environment         = var.environment
}
