
module "grafana" {
  source                 = "../modules/apps/grafana"
  root_domain            = var.root_domain
  namespace              = var.namespace_monitoring
  grafana_admin_password = var.grafana_admin_password
  
  # Identity settings passed from parent
  grafana_client_id      = var.grafana_client_id
  grafana_client_secret  = var.grafana_client_secret
  issuer_url             = var.issuer_url
  environment            = var.environment
  infra_namespace        = var.namespace_infra
}

module "headlamp" {
  source               = "../modules/apps/headlamp"
  root_domain          = var.root_domain
  namespace            = var.namespace_infra
  
  oidc_client_id       = var.headlamp_client_id
  oidc_client_secret   = var.headlamp_client_secret
  issuer_url           = var.issuer_url
  environment          = var.environment
}

module "rover" {
  source      = "../modules/apps/rover"
  namespace   = var.namespace_infra
  environment = var.environment
  root_domain = var.root_domain
}
