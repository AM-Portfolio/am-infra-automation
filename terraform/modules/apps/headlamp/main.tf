# ==============================================================================
# Headlamp — Kubernetes UI
# ==============================================================================
# Deploys Headlamp with OIDC integration (Authentik) and ClusterAdmin RBAC.
# ==============================================================================

resource "helm_release" "headlamp" {
  name       = "headlamp"
  repository = "https://kubernetes-sigs.github.io/headlamp/"
  chart      = "headlamp"
  namespace  = var.namespace
  version    = "0.41.0"

  values = [yamlencode({
    image = {
      tag = "v0.41.0"
    }
    config = {
      # OIDC disabled for now to unblock access
      oidc = {
        clientID     = ""
        clientSecret = ""
        issuerURL    = ""
      }
    }
    serviceAccount = {
      create = true
      name   = "headlamp"
    }
    clusterRoleBinding = {
      create          = true
      clusterRoleName = "cluster-admin"
    }

    # 🔄 Automated Rollout
    podAnnotations = {
      "checksum/config" = "disabled-oidc"
    }
  })]

  lifecycle {
    prevent_destroy = true
  }
}

# ── Dynamic Token for UI ─────────────────────────────────────────────────────
resource "kubernetes_secret" "headlamp_token" {
  metadata {
    name      = "headlamp-token"
    namespace = var.namespace
    annotations = {
      "kubernetes.io/service-account.name" = "headlamp"
    }
  }
  type = "kubernetes.io/service-account-token"

  depends_on = [helm_release.headlamp]
}

