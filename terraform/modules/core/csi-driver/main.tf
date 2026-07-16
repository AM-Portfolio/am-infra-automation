# ------------------------------------------------------------------------------
# Kubernetes Secrets Store CSI Driver
# ------------------------------------------------------------------------------

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
    }
  }
}

resource "helm_release" "csi_secrets_store" {
  name       = "csi-secrets-store"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  namespace  = "kube-system"
  version    = "1.4.2"

  values = [yamlencode({
    syncSecret = {
      enabled = true # Optional: allows syncing CSI mounts to K8s secrets
    }
    enableSecretRotation = true
  })]
}
