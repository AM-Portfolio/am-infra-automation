# ------------------------------------------------------------------------------
# LOCAL ENVIRONMENT PROVIDERS configuration for access layer
# ------------------------------------------------------------------------------

terraform {
  backend "local" {}

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.24"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = "2024.2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
  }
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}

# 1.5. Remote State for Token Recovery
data "terraform_remote_state" "identity" {
  backend = "local"
  config = {
    path = "../../identity/local/terraform.tfstate"
  }
}

# 2. Dynamic Vault Token Extraction
data "kubernetes_secret" "vault_keys" {
  metadata {
    name      = "vault-unseal-keys"
    namespace = "vault"
  }
}

locals {
  vault_root_token_effective = var.vault_root_token != "" ? var.vault_root_token : jsondecode(data.kubernetes_secret.vault_keys.data["keys.json"]).root_token
}

# 3. Vault provider — read token dynamically
provider "vault" {
  address = "http://localhost:8200"
  token   = local.vault_root_token_effective
}

# ── Read Identity secrets from Vault ──────────────────────────────────────────
data "vault_kv_secret_v2" "identity_bootstrap" {
  mount = "secret"
  name  = "${var.environment}/infra/identity"
}

# ── Read Permanent Automation Token from Vault ────────────────────────────────
data "vault_generic_secret" "authentik_token" {
  path = "secret/infra/identity/automation"
}

locals {
  raw_auto_token = lookup(data.vault_generic_secret.authentik_token.data, "terraform_token", "")
  effective_authentik_token = (var.authentik_token != "") ? var.authentik_token : (
    (local.raw_auto_token != "" && local.raw_auto_token != "<nil>") ? local.raw_auto_token : data.vault_kv_secret_v2.identity_bootstrap.data["authentik_bootstrap_token"]
  )
}

# Authentik provider — prioritizing bootstrap token for local stability
provider "authentik" {
  url   = "http://localhost:9001"
  token = local.effective_authentik_token
}
