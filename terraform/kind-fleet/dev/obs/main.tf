# Phase 4h — Fleet DEV observability on am-dev-platform (Grafana + Loki + Prometheus).
# Shared bare FQDNs (interim hub until VPS2): grafana/loki/prometheus.asrax.in
# State: ~/.asrax/tfstate/dev/obs/

locals {
  env       = "dev"
  domain    = "asrax.in"
  namespace = "monitoring"
  grafana_url               = "https://grafana.asrax.in"
  loki_push_url             = "https://loki.asrax.in/loki/api/v1/push"
  prometheus_remote_write_url = "https://prometheus.asrax.in/api/v1/write"
}

resource "terraform_data" "env_folder_guard" {
  input = local.env
  lifecycle {
    precondition {
      condition     = local.env == "dev"
      error_message = "kind-fleet/dev/obs must set local.env = \"dev\"."
    }
  }
}

data "external" "platform_node_ip" {
  program = ["PowerShell", "-NoProfile", "-File", "${path.module}/../platform/scripts/platform-ip.ps1"]
}

# Read grafana OIDC secret from Vault (written by platform stack) when token present.
data "external" "grafana_oidc" {
  program = ["PowerShell", "-NoProfile", "-Command", <<-PS
    $ErrorActionPreference = 'Stop'
    $addr = $env:VAULT_ADDR; if (-not $addr) { $addr = 'https://vault-dev.asrax.in' }
    $tok = $env:TF_VAR_vault_token
    if (-not $tok -and (Test-Path "$env:USERPROFILE\.asrax\vault-dev-infra.json")) {
      $tok = (Get-Content "$env:USERPROFILE\.asrax\vault-dev-infra.json" -Raw | ConvertFrom-Json).root_token
    }
    $cid = 'grafana'; $sec = ''
    if ($tok) {
      try {
        $r = Invoke-RestMethod -Uri "$addr/v1/apps/data/dev/oidc/grafana" -Headers @{ 'X-Vault-Token' = $tok }
        if ($r.data.data.client_id) { $cid = $r.data.data.client_id }
        if ($r.data.data.client_secret) { $sec = $r.data.data.client_secret }
      } catch {}
    }
    if (-not $sec) { $sec = 'dev-fleet-grafana-oidc-placeholder' }
    @{ client_id = $cid; client_secret = $sec } | ConvertTo-Json -Compress
  PS
  ]
}

resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = local.namespace
    labels = {
      environment = local.env
      managed-by  = "terraform"
      role        = "observability"
    }
  }
}

module "obs_stack" {
  source = "../../../modules/apps/grafana"

  environment            = local.env
  root_domain            = local.domain
  namespace              = local.namespace
  grafana_admin_user     = "admin"
  grafana_admin_password = random_password.grafana_admin.result
  grafana_client_id      = data.external.grafana_oidc.result.client_id
  grafana_client_secret  = data.external.grafana_oidc.result.client_secret
  issuer_url             = "https://auth-dev.asrax.in/realms/am-realm"
  oidc_provider          = "keycloak"
  disable_login_form     = false # set true at ZT-P1 / Phase 10 with Access enforce
  enable_node_selector   = false
  enable_promtail        = false
  enable_gateway         = false
  enable_persistence     = true
  storage_class          = "standard"
  grafana_service_type    = "NodePort"
  loki_service_type       = "NodePort"
  prometheus_service_type = "NodePort"
  grafana_node_port       = 30350
  loki_node_port          = 30310
  prometheus_node_port    = 30311
  use_bare_fqdn           = true

  depends_on = [kubernetes_namespace_v1.monitoring]
}

# Bridge Grafana + Loki into infra Traefik (same pattern as Keycloak/Argo).
# backend_host = Docker DNS — IP resolved at apply; post-restart also run scripts/refresh-platform-bridges.ps1
module "route_grafana" {
  source = "../../../modules/core/cross-cluster-http"
  providers = {
    kubernetes = kubernetes.infra
    kubectl    = kubectl.infra
  }
  environment    = local.env
  root_domain    = local.domain
  namespace      = "infra"
  host_label     = "grafana"
  use_bare_fqdn  = true
  service_name   = "grafana-platform"
  service_port   = 80
  backend_host   = "am-${local.env}-platform-control-plane"
  backend_ip     = var.platform_node_ip
  backend_port   = module.obs_stack.grafana_node_port

  depends_on = [module.obs_stack]
}

module "route_loki" {
  source = "../../../modules/core/cross-cluster-http"
  providers = {
    kubernetes = kubernetes.infra
    kubectl    = kubectl.infra
  }
  environment    = local.env
  root_domain    = local.domain
  namespace      = "infra"
  host_label     = "loki"
  use_bare_fqdn  = true
  service_name   = "loki-platform"
  service_port   = 80
  backend_host   = "am-${local.env}-platform-control-plane"
  backend_ip     = var.platform_node_ip
  backend_port   = module.obs_stack.loki_node_port

  depends_on = [module.obs_stack]
}

module "route_prometheus" {
  source = "../../../modules/core/cross-cluster-http"
  providers = {
    kubernetes = kubernetes.infra
    kubectl    = kubectl.infra
  }
  environment    = local.env
  root_domain    = local.domain
  namespace      = "infra"
  host_label     = "prometheus"
  use_bare_fqdn  = true
  service_name   = "prometheus-platform"
  service_port   = 80
  backend_host   = "am-${local.env}-platform-control-plane"
  backend_ip     = var.platform_node_ip
  backend_port   = module.obs_stack.prometheus_node_port

  depends_on = [module.obs_stack]
}

# Persist Grafana admin password to Vault (names path only for ops).
resource "null_resource" "vault_grafana_admin" {
  count = var.vault_token != "" ? 1 : 0

  triggers = {
    pw   = sha256(random_password.grafana_admin.result)
    urls = "bare-v1"
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    environment = {
      VAULT_ADDR  = var.vault_addr
      VAULT_TOKEN = var.vault_token
      ADMIN_PW    = random_password.grafana_admin.result
    }
    command = <<-PS
      $path = 'apps/data/dev/infra/observability'
      $body = @{ data = @{ data = @{
        GRAFANA_ADMIN_USER = 'admin'
        GRAFANA_ADMIN_PASSWORD = $env:ADMIN_PW
        GRAFANA_URL = 'https://grafana.asrax.in'
        LOKI_URL = 'https://loki.asrax.in'
        PROMETHEUS_URL = 'https://prometheus.asrax.in'
      } } } | ConvertTo-Json -Depth 5
      try {
        Invoke-RestMethod -Method Post -Uri "$($env:VAULT_ADDR)/v1/$path" -Headers @{ 'X-Vault-Token' = $env:VAULT_TOKEN } -ContentType 'application/json' -Body $body | Out-Null
        Write-Output "vault_ok=$path"
      } catch { Write-Output "vault_warn=$($_.Exception.Message)" }
    PS
  }
}

output "grafana_url" { value = local.grafana_url }
output "loki_push_url" { value = local.loki_push_url }
output "prometheus_remote_write_url" { value = local.prometheus_remote_write_url }
output "prometheus_node_port" { value = module.obs_stack.prometheus_node_port }
output "grafana_admin_password" {
  value     = random_password.grafana_admin.result
  sensitive = true
}
output "platform_node_ip" {
  value = var.platform_node_ip != "" ? var.platform_node_ip : data.external.platform_node_ip.result.ip
}
