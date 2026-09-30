# In-cluster HTTP proxy so Cloudflare Tunnel can forward Kubernetes bearer tokens.
# Contabo Argo → kubeapi-*.asrax.in → cloudflared → this Service → https://kubernetes.default.svc
# Never point the tunnel at https://kubernetes.default.svc directly (bearer → 401).

variable "namespace" {
  type        = string
  default     = "infra"
  description = "Must be the same NS as cloudflared (usually infra)."
}

variable "nginx_image" {
  type    = string
  default = "nginx:1.27-alpine"
}

locals {
  labels = { app = "kubeapi-proxy" }
}

resource "kubernetes_config_map_v1" "nginx" {
  metadata {
    name      = "kubeapi-proxy-nginx"
    namespace = var.namespace
    labels    = local.labels

    
  }

  data = {
    "nginx.conf" = <<-NGINX
      worker_processes 1;
      error_log /dev/stderr warn;
      events { worker_connections 1024; }
      http {
        access_log /dev/stdout;
        server {
          listen 80;
          location / {
            proxy_http_version 1.1;
            proxy_set_header Host $$host;
            proxy_set_header Authorization $$http_authorization;
            proxy_set_header Connection "";
            proxy_ssl_server_name on;
            proxy_ssl_verify off;
            # Argo watches are long-lived; default 60s read timeout -> Contabo API 504
            proxy_buffering off;
            proxy_request_buffering off;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
            proxy_connect_timeout 30s;
            proxy_pass https://kubernetes.default.svc;
          }
        }
      }
    NGINX
  }
}

resource "kubernetes_deployment_v1" "proxy" {
  metadata {
    name      = "kubeapi-proxy"
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        container {
          name  = "nginx"
          image = var.nginx_image

          port {
            container_port = 80
            name           = "http"
          }

          volume_mount {
            name       = "conf"
            mount_path = "/etc/nginx/nginx.conf"
            sub_path   = "nginx.conf"
          }

          resources {
            requests = {
              cpu    = "20m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "64Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/version"
              port = 80
              http_header {
                name  = "Host"
                value = "kubernetes.default.svc"
              }
            }
            initial_delay_seconds = 5
            period_seconds        = 15
          }

          readiness_probe {
            http_get {
              path = "/version"
              port = 80
              http_header {
                name  = "Host"
                value = "kubernetes.default.svc"
              }
            }
            initial_delay_seconds = 3
            period_seconds        = 10
          }
        }

        volume {
          name = "conf"
          config_map {
            name = kubernetes_config_map_v1.nginx.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "proxy" {
  metadata {
    name      = "kubeapi-proxy"
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    selector = local.labels

    port {
      name        = "http"
      port        = 80
      target_port = 80
    }
  }
}

output "origin_url" {
  value       = "http://kubeapi-proxy.${var.namespace}.svc.cluster.local:80"
  description = "Cloudflare tunnel service URL for kubeapi-*.asrax.in"
}

output "http_host_header" {
  value       = "kubernetes.default.svc"
  description = "cloudflared originRequest.httpHostHeader"
}
