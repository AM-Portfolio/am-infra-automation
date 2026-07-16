# ==============================================================================
# GATEWAY LAYER — Providers (local environment)
# ==============================================================================

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.24"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

provider "kubernetes" {
  host             = "https://127.0.0.1:6443"
  insecure         = true
  config_path      = "../../../k8s/kubeconfig.local"
}

provider "helm" {
  kubernetes {
    host             = "https://127.0.0.1:6443"
    insecure         = true
    config_path      = "../../../k8s/kubeconfig.local"
  }
}

provider "kubectl" {
  host             = "https://127.0.0.1:6443"
  load_config_file = true
  insecure         = true
  config_path      = "../../../k8s/kubeconfig.local"
}

# ── Dynamic Vault Token Extraction ──────────────────────────────────────────
# We fetch the root token produced by the unsealer script from the K8s secret.
# This ensures a zero-touch bootstrap experience for all layers.
data "kubernetes_secret" "vault_keys" {
  metadata {
    name      = "vault-unseal-keys"
    namespace = "vault"
  }
}

locals {
  vault_root_token = jsondecode(data.kubernetes_secret.vault_keys.data["keys.json"]).root_token
}

# Vault provider — points to the local port-forward tunnel (8200)
# This requires 'manage.js' to be running the background tunnel.
provider "vault" {
  address = "http://127.0.0.1:8200"
  token   = local.vault_root_token
}

# Cloudflare Provider — authenticated via Verified API Token from Vault
# (Fallback to environment variable if Vault read fails)
provider "cloudflare" {
  api_token = coalesce(lookup(data.vault_kv_secret_v2.cloudflare_api.data, "cloudflare_api_token", ""), var.cloudflare_api_token)
}

data "vault_kv_secret_v2" "cloudflare_api" {
  mount = "secret"
  name  = "${var.environment}/infra/gateway"
}
