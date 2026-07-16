# ==============================================================================
# ADMIN LAYER — Providers (Local Environment)
# ==============================================================================

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0" # Aligned with gateway/exposer
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.17.0" # Aligned with gateway/exposer
    }
    vault = {
      source  = "hashicorp/vault"
      version = "3.25.0" # Aligned with gateway/exposer
    }
  }
}

# 1. Kubernetes Provider — Uses the central foundation config
provider "kubernetes" {
  host             = "https://127.0.0.1:6443"
  insecure         = true
  config_path      = "../../foundation/am-local-config"
}

# 2. Helm Provider — Uses matching cluster configuration
provider "helm" {
  kubernetes {
    host             = "https://127.0.0.1:6443"
    insecure         = true
    config_path      = "../../foundation/am-local-config"
  }
}

# 3. Dynamic Vault Token Extraction — Reuses cluster secrets for zero-touch auth
data "kubernetes_secret" "vault_keys" {
  metadata {
    name      = "vault-unseal-keys"
    namespace = "vault"
  }
}

locals {
  # Fish the root token from the cluster secret; fallback to manual var if needed
  vault_root_token = jsondecode(data.kubernetes_secret.vault_keys.data["keys.json"]).root_token
}

# 4. Vault Provider — Authenticated for secret persistence
provider "vault" {
  address = "http://127.0.0.1:8200"
  token   = local.vault_root_token
}
