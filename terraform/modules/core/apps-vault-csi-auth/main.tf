# Apps-cluster Vault CSI auth (G25): reviewer SA, Vault kubernetes-{path} auth,
# am-backend-role bound to apps+agents NS, optional GHCR pull secrets.
# Prefer this over setup-g25-vault-auth.ps1.

locals {
  bound_namespaces  = [var.apps_ns, var.agents_ns]
  pull_secret_names = ["github-registry-secret", "regcred", "ghcr-creds"]
  # Keys must not derive from sensitive values (ghcr_token) — gate via create_pull_secrets only.
  pull_secret_map = var.create_pull_secrets ? {
    for pair in setproduct(local.bound_namespaces, local.pull_secret_names) :
    "${pair[0]}.${pair[1]}" => { ns = pair[0], name = pair[1] }
  } : {}
  dockerconfig = {
    auths = {
      "ghcr.io" = {
        username = var.ghcr_username != "" ? var.ghcr_username : "token"
        password = var.ghcr_token
        auth     = base64encode("${var.ghcr_username != "" ? var.ghcr_username : "token"}:${var.ghcr_token}")
      }
    }
  }
}

# --- Apps cluster: TokenReviewer for Vault ---

resource "kubernetes_service_account_v1" "vault_auth_reviewer" {
  metadata {
    name      = "vault-auth-reviewer"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "am.asrax.in/role"             = "vault-csi-reviewer"
    }
  }
}

resource "kubernetes_cluster_role_binding_v1" "vault_auth_reviewer" {
  metadata {
    name = "vault-auth-reviewer-apps"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.vault_auth_reviewer.metadata[0].name
    namespace = "kube-system"
  }
}

resource "kubernetes_token_request_v1" "vault_auth_reviewer" {
  metadata {
    name      = kubernetes_service_account_v1.vault_auth_reviewer.metadata[0].name
    namespace = "kube-system"
  }
  spec {
    expiration_seconds = 31536000 # 365d
  }

  depends_on = [kubernetes_cluster_role_binding_v1.vault_auth_reviewer]
}

# --- Vault: policy + kubernetes auth for apps CSI ---

resource "vault_policy" "am_apps_read" {
  name = var.policy_name
  policy = <<-EOT
    path "apps/data/${var.env}/*" { capabilities = ["create","read","update","list"] }
    path "apps/metadata/${var.env}/*" { capabilities = ["list"] }
    path "apps/data/${var.env}/runtime/*" { capabilities = ["create","read","update","list"] }
    path "apps/metadata/${var.env}/runtime/*" { capabilities = ["list"] }
    path "secret/data/${var.env}/*" { capabilities = ["read","list"] }
    path "secret/metadata/${var.env}/*" { capabilities = ["list"] }
  EOT
}

resource "vault_auth_backend" "kubernetes_apps" {
  type = "kubernetes"
  path = var.auth_path
}

resource "vault_kubernetes_auth_backend_config" "apps" {
  backend                = vault_auth_backend.kubernetes_apps.path
  kubernetes_host        = var.kubernetes_host
  kubernetes_ca_cert     = var.kubernetes_ca_cert_pem
  token_reviewer_jwt     = kubernetes_token_request_v1.vault_auth_reviewer.token
  disable_iss_validation = true
}

resource "vault_kubernetes_auth_backend_role" "am_backend" {
  backend                          = vault_auth_backend.kubernetes_apps.path
  role_name                        = var.role_name
  bound_service_account_names      = ["am-backend-sa"]
  bound_service_account_namespaces = local.bound_namespaces
  token_policies                   = [vault_policy.am_apps_read.name]
  token_ttl                        = 3600
  token_max_ttl                    = 7200

  depends_on = [vault_kubernetes_auth_backend_config.apps]
}

# --- GHCR pull secrets in apps + agents NS ---

resource "kubernetes_secret_v1" "ghcr" {
  for_each = local.pull_secret_map

  metadata {
    name      = each.value.name
    namespace = each.value.ns
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = jsonencode(local.dockerconfig)
  }
}
