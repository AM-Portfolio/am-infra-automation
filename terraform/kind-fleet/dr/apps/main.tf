# Phase 4a — DR apps Kind cluster + NS + G25 Vault CSI auth.
# Computed Kind name: am-dr-apps API :6444
# Host state: /data/am-state/terraform/dr/apps/
# Apply on VPS3 only.
#
# If Kind already exists (G1) and state is empty: adopt — never kind delete:
#   scripts/kind-fleet/adopt-kind-cluster.sh am-dr-apps

locals {
  env                  = "dr"
  domain               = "asrax.in"
  apps_kubeconfig      = "/data/am-state/kubeconfig.am-dr-apps.yaml"
  vault_keys_file      = "/data/am-state/vault-dr-infra.json"
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
      condition     = local.env == "dr"
      error_message = "kind-fleet/dr/apps must set local.env = \"dr\"."
    }
  }
}

module "cluster" {
  source             = "../../../modules/core/cluster"
  env                = local.env
  cluster_role       = "apps"
  node_shape         = "one"
  vps_ram_gb         = 32
  api_server_address = "0.0.0.0"
  vps_ip             = "129.121.128.131"
  config_output_path = local.apps_kubeconfig
  oidc_issuer_url    = "https://auth-dr.asrax.in/realms/am-realm"
  oidc_client_id     = "kubectl"
}

resource "null_resource" "kubeconfig_asrax" {
  triggers = {
    cluster = module.cluster.cluster_name
  }
  provisioner "local-exec" {
    # Cert SANs are VPS IP + docker IP (not 127.0.0.1) — rewrite before k8s/helm providers use the file.
    command = <<-EOT
      mkdir -p /home/am-ops/.asrax
      python3 -c 'from pathlib import Path; p=Path("${local.apps_kubeconfig}"); t=p.read_text(); p.write_text(t.replace("https://127.0.0.1:6444","https://129.121.128.131:6444").replace("https://0.0.0.0:6444","https://129.121.128.131:6444"))'
      cp -f ${local.apps_kubeconfig} /home/am-ops/.asrax/kubeconfig.am-dr-apps.yaml
      chmod 600 ${local.apps_kubeconfig} /home/am-ops/.asrax/kubeconfig.am-dr-apps.yaml
      chown am-ops:am-ops /home/am-ops/.asrax/kubeconfig.am-dr-apps.yaml || true
      iptables -t nat -C PREROUTING -p tcp --dport 6444 -j DNAT --to-destination 127.0.0.1:6444 2>/dev/null || iptables -t nat -A PREROUTING -p tcp --dport 6444 -j DNAT --to-destination 127.0.0.1:6444 || true
    EOT
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
