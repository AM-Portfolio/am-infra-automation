locals {
  kubeconfig = "/data/am-state/kubeconfig.am-prod-infra.yaml"
  env        = "prod"
  domain     = "asrax.in"
}

provider "kubernetes" {
  config_path    = local.kubeconfig
  config_context = "kind-am-prod-infra"
}

provider "helm" {
  kubernetes {
    config_path    = local.kubeconfig
    config_context = "kind-am-prod-infra"
  }
}

provider "kubectl" {
  config_path      = local.kubeconfig
  config_context   = "kind-am-prod-infra"
  load_config_file = true
}

# Live Vault (exposer :8200 → NodePort 30820). Required for vault/oidc.tf + MinIO optional KV.
provider "vault" {
  address = "http://127.0.0.1:8200"
  token = try(
    jsondecode(replace(file("/data/am-state/vault-prod-infra.json"), "\ufeff", "")).root_token,
    ""
  )
  skip_child_token = true
  skip_tls_verify  = true
}

provider "authentik" {
  url   = "http://127.0.0.1:9000"
  token = "unused"
}

provider "postgresql" {
  host            = "127.0.0.1"
  port            = 5432
  username        = "postgres"
  password        = "unused"
  sslmode         = "disable"
  superuser       = false
  connect_timeout = 5
}

provider "mongodbatlas" {
  public_key  = "unused"
  private_key = "unused"
}
