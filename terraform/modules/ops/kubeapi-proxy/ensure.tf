# In-cluster healer: if kubeapi-proxy is missing/unready, re-apply manifests.
# Survives pod deletes while Kind is up. After Kind wipe, host Docker ensure
# (am-kubeapi-proxy-ensure) re-applies — same pattern as am-port-exposer.

variable "enable_ensure" {
  type        = bool
  default     = true
  description = "Deploy kubeapi-proxy-ensure loop in-cluster."
}

variable "kubectl_image" {
  type    = string
  default = "alpine/k8s:1.31.4"
}

variable "ensure_interval_seconds" {
  type    = number
  default = 30
}

locals {
  ensure_labels = { app = "kubeapi-proxy-ensure" }
  proxy_yaml    = file("${path.module}/kubeapi-proxy.yaml")
}

resource "kubernetes_service_account_v1" "ensure" {
  count = var.enable_ensure ? 1 : 0

  metadata {
    name      = "kubeapi-proxy-ensure"
    namespace = var.namespace
    labels    = local.ensure_labels
  }
}

resource "kubernetes_role_v1" "ensure" {
  count = var.enable_ensure ? 1 : 0

  metadata {
    name      = "kubeapi-proxy-ensure"
    namespace = var.namespace
    labels    = local.ensure_labels
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps", "services", "pods", "endpoints"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding_v1" "ensure" {
  count = var.enable_ensure ? 1 : 0

  metadata {
    name      = "kubeapi-proxy-ensure"
    namespace = var.namespace
    labels    = local.ensure_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.ensure[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.ensure[0].metadata[0].name
    namespace = var.namespace
  }
}

resource "kubernetes_config_map_v1" "ensure_manifest" {
  count = var.enable_ensure ? 1 : 0

  metadata {
    name      = "kubeapi-proxy-ensure-manifest"
    namespace = var.namespace
    labels    = local.ensure_labels
  }

  data = {
    "kubeapi-proxy.yaml" = local.proxy_yaml
  }
}

resource "kubernetes_deployment_v1" "ensure" {
  count = var.enable_ensure ? 1 : 0

  metadata {
    name      = "kubeapi-proxy-ensure"
    namespace = var.namespace
    labels    = local.ensure_labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = local.ensure_labels
    }

    template {
      metadata {
        labels = local.ensure_labels
      }

      spec {
        service_account_name = kubernetes_service_account_v1.ensure[0].metadata[0].name
        restart_policy       = "Always"

        container {
          name  = "ensure"
          image = var.kubectl_image

          command = ["/bin/bash", "-ec"]
          args = [<<-SCRIPT
            INTERVAL="${var.ensure_interval_seconds}"
            MANIFEST="/manifests/kubeapi-proxy.yaml"
            echo "kubeapi-proxy-ensure started interval=$${INTERVAL}s"
            while true; do
              ready="$(kubectl -n ${var.namespace} get deploy kubeapi-proxy -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
              if [[ "$${ready:-0}" != "1" ]]; then
                echo "$(date -u +%FT%TZ) proxy not ready (ready=$${ready:-0}); applying"
                kubectl apply -f "$$MANIFEST" || true
                kubectl -n ${var.namespace} rollout status deploy/kubeapi-proxy --timeout=60s || true
              else
                echo "$(date -u +%FT%TZ) kubeapi-proxy ready=1"
              fi
              sleep "$$INTERVAL"
            done
          SCRIPT
          ]

          volume_mount {
            name       = "manifests"
            mount_path = "/manifests"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }

        volume {
          name = "manifests"
          config_map {
            name = kubernetes_config_map_v1.ensure_manifest[0].metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_deployment_v1.proxy,
    kubernetes_service_v1.proxy,
  ]
}
