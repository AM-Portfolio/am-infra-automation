# Phase 4a — prod apps Kind cluster + NS + G25 Vault CSI auth.
# Computed Kind name: am-prod-apps API :6444
# Host state: /data/am-state/terraform/prod/apps/
# Apply on VPS1 only.

locals {
  env                 = "prod"
  domain              = "asrax.in"
  apps_kubeconfig     = "/data/am-state/kubeconfig.am-prod-apps.yaml"
  vault_keys_file     = "/data/am-state/vault-prod-infra.json"
  # Prefer am-ops-readable paths (terraform runs as am-ops on VPS).
  credentials_env_file = "/data/am-state/credentials/credentials.env"
}

module "naming" {
  source = "../../../modules/core/fleet-naming"
  env    = local.env
  domain = local.domain
}

resource "terraform_data" "env_folder_guard" {
  input = local.env
  lifecycle {
    precondition {
      condition     = local.env == "prod"
      error_message = "kind-fleet/prod/apps must set local.env = \"prod\"."
    }
  }
}

module "cluster" {
  source             = "../../../modules/core/cluster"
  env                = local.env
  cluster_role       = "apps"
  node_shape         = "one"
  vps_ram_gb         = 64
  api_server_address = "0.0.0.0"
  vps_ip             = "203.174.22.129"
  config_output_path = local.apps_kubeconfig
}

resource "null_resource" "kubeconfig_asrax" {
  triggers = {
    cluster = module.cluster.cluster_name
  }
  provisioner "local-exec" {
    command = "mkdir -p /home/am-ops/.asrax && cp -f ${local.apps_kubeconfig} /home/am-ops/.asrax/kubeconfig.am-prod-apps.yaml && chmod 600 /home/am-ops/.asrax/kubeconfig.am-prod-apps.yaml && chown am-ops:am-ops /home/am-ops/.asrax/kubeconfig.am-prod-apps.yaml || true"
  }
  depends_on = [module.cluster]
}

# Phase 4: apps + agents NS + edge (not infra/vault on this cluster).
resource "kubernetes_namespace" "am_apps" {
  metadata {
    name = module.naming.apps_ns
    labels = {
      environment = local.env
      managed-by  = "terraform"
      role        = "apps"
    }
  }

  depends_on = [module.cluster, null_resource.kubeconfig_asrax]
}

resource "kubernetes_namespace" "am_agents" {
  metadata {
    name = module.naming.agents_ns
    labels = {
      environment = local.env
      managed-by  = "terraform"
      role        = "agents"
    }
  }

  depends_on = [module.cluster, null_resource.kubeconfig_asrax]
}

resource "kubernetes_namespace" "edge" {
  metadata {
    name = "edge"
  }

  depends_on = [module.cluster, null_resource.kubeconfig_asrax]
}

# CSI Secrets Store + Vault provider (Kind 1.27 → chart 1.4.x)
resource "helm_release" "csi_secrets_store" {
  name       = "csi-secrets-store"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  namespace  = "kube-system"
  version    = "1.4.8"
  wait       = true
  timeout    = 600

  values = [yamlencode({
    syncSecret = {
      enabled = true
    }
    enableSecretRotation = true
    linux = {
      providerVolume = "/etc/kubernetes/secrets-store-csi-providers"
    }
  })]

  depends_on = [module.cluster, null_resource.kubeconfig_asrax]
}

resource "helm_release" "vault_csi_provider" {
  name       = "vault-csi-provider"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  namespace  = "kube-system"
  version    = "0.29.1"
  wait       = true
  timeout    = 600

  values = [yamlencode({
    global = {
      enabled = false
    }
    injector = {
      enabled = false
    }
    server = {
      enabled = false
    }
    csi = {
      enabled = true
      agent = {
        enabled = true
        image = {
          repository = "hashicorp/vault"
        }
      }
      daemonSet = {
        providersDir = "/etc/kubernetes/secrets-store-csi-providers"
      }
    }
  })]

  depends_on = [helm_release.csi_secrets_store]
}

resource "kubernetes_service_account" "am_backend_sa" {
  metadata {
    name      = "am-backend-sa"
    namespace = kubernetes_namespace.am_apps.metadata[0].name
  }
  automount_service_account_token = true

  image_pull_secret { name = "github-registry-secret" }
  image_pull_secret { name = "regcred" }
  image_pull_secret { name = "ghcr-creds" }

  depends_on = [kubernetes_namespace.am_apps, module.vault_csi_auth]
}

resource "kubernetes_service_account" "am_backend_sa_agents" {
  metadata {
    name      = "am-backend-sa"
    namespace = kubernetes_namespace.am_agents.metadata[0].name
  }
  automount_service_account_token = true

  image_pull_secret { name = "github-registry-secret" }
  image_pull_secret { name = "regcred" }
  image_pull_secret { name = "ghcr-creds" }

  depends_on = [kubernetes_namespace.am_agents, module.vault_csi_auth]
}

output "cluster_name" {
  value = module.cluster.cluster_name
}

output "api_server_port" {
  value = module.cluster.api_server_port
}

output "apps_ns" {
  value = kubernetes_namespace.am_apps.metadata[0].name
}

output "agents_ns" {
  value = kubernetes_namespace.am_agents.metadata[0].name
}

output "vault_url" {
  value = module.naming.vault_url
}

output "ui_host" {
  value = module.naming.ui_host
}

output "kubeconfig_path" {
  value = local.apps_kubeconfig
}
