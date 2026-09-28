# ==============================================================================
# Headlamp — Kubernetes UI (Keycloak OIDC)
# ==============================================================================
# Fleet iam-sso Phase 2: enable OIDC when issuer_url + client id/secret set.
# ==============================================================================

locals {
  oidc_enabled = var.issuer_url != "" && var.oidc_client_id != "" && var.oidc_client_secret != ""
}

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
      oidc = local.oidc_enabled ? {
        clientID     = var.oidc_client_id
        clientSecret = var.oidc_client_secret
        issuerURL    = var.issuer_url
        scopes       = "openid profile email roles groups"
      } : {
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
    podAnnotations = {
      "checksum/oidc" = local.oidc_enabled ? sha256("${var.issuer_url}:${var.oidc_client_id}") : "disabled-oidc"
    }
  })]

  lifecycle {
    prevent_destroy = true
  }
}

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
