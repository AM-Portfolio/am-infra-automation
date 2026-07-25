# ==============================================================================
# LOCAL ENVIRONMENT: MONITORING ENTRYPOINT
# ==============================================================================

terraform {
  backend "local" {}
}

data "terraform_remote_state" "foundation" {
  backend = "local"
  config = {
    path = "/data/am-state/foundation.tfstate"
  }
}

locals {
  creds = data.terraform_remote_state.foundation.outputs.credentials
}

module "monitoring" {
  source = "./.."

  root_domain            = var.root_domain
  namespace_monitoring   = data.terraform_remote_state.foundation.outputs.monitoring_ns
  namespace_infra        = data.terraform_remote_state.foundation.outputs.infra_ns
  
  # Identity & SSO (OIDC) Standard Chain
  issuer_url             = var.oidc_issuer_url
  grafana_client_id      = var.grafana_client_id
  grafana_client_secret  = var.grafana_client_secret
  headlamp_client_id     = var.headlamp_client_id
  headlamp_client_secret = var.headlamp_client_secret

  # Credential Management: Use provided variable or fallback to foundation creds
  grafana_admin_password = var.grafana_password  != "" ? var.grafana_password  : local.creds.authentik_bootstrap
  influxdb_password      = var.influxdb_password != "" ? var.influxdb_password : local.creds.influx_token
  influxdb_token         = var.influxdb_token      != "" ? var.influxdb_token      : local.creds.influx_token
  postgresql_password    = var.postgresql_password != "" ? var.postgresql_password : local.creds.postgres_root
}
