module "influxdb" {
  source          = "../modules/apps/influxdb"
  root_domain     = var.root_domain
  namespace       = var.namespace_infra
  influx_password  = var.influxdb_password
  influx_token     = var.influxdb_token
  environment      = var.environment
}
