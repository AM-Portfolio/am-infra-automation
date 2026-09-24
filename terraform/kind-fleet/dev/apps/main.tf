# Phase 4a — apps Kind cluster (laptop/dev). Prod/DR later.
# Computed Kind name: am-dev-apps API :6444
# Host state: terraform init -backend-config=backend.hcl → ~/.asrax/tfstate/dev/apps/

locals {
  env    = "dev"
  domain = "asrax.in"
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
      condition     = local.env == "dev"
      error_message = "kind-fleet/dev/apps must set local.env = \"dev\"."
    }
  }
}

module "cluster" {
  source          = "../../../modules/core/cluster"
  env             = local.env
  cluster_role    = "apps"
  api_server_port = 6444
  node_shape      = "one"
}

resource "local_file" "kubeconfig" {
  content         = module.cluster.kubeconfig
  filename        = pathexpand(module.naming.kubeconfig_apps)
  file_permission = "0600"
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

  depends_on = [module.cluster, local_file.kubeconfig]
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

  depends_on = [module.cluster, local_file.kubeconfig]
}

resource "kubernetes_namespace" "edge" {
  metadata {
    name = "edge"
  }

  depends_on = [module.cluster, local_file.kubeconfig]
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

  # Pull secrets come from module.vault_csi_auth (vault-csi-auth.tf)
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
  value = pathexpand(module.naming.kubeconfig_apps)
}
