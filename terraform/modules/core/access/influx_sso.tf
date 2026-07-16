# ------------------------------------------------------------------------------
# InfluxDB UI SSO — Forward Auth (Single Application)
# ------------------------------------------------------------------------------

resource "authentik_application" "influx" {
  name              = "InfluxDB UI"
  slug              = "influxdb-ui"
  protocol_provider = authentik_provider_proxy.influx_proxy.id
  meta_icon         = "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/svg/influxdb.svg"
  meta_launch_url   = "https://influx${local.domain_suffix}.${var.root_domain}"
  group             = "Data Stores"
}

resource "authentik_provider_proxy" "influx_proxy" {
  name               = "influx-proxy"
  internal_host      = "http://influxdb-influxdb2.infra.svc.cluster.local:80"
  external_host      = "https://influx${local.domain_suffix}.${var.root_domain}"
  mode               = "forward_single"
  authorization_flow = data.authentik_flow.implicit_consent.id
  property_mappings  = [authentik_scope_mapping.influx_token_auth.id]
}
