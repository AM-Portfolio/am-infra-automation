# ==============================================================================
# Terraform Rover — State Visualization
# ==============================================================================

resource "kubernetes_config_map" "rover_dummy" {
  metadata {
    name      = "rover-dummy-tf"
    namespace = var.namespace
  }

  data = {
    "main.tf" = <<EOF
# Dummy file to allow Rover to start
variable "placeholder" {
  default = "hello"
}
EOF
  }
}

resource "kubernetes_deployment" "rover" {
  metadata {
    name      = "rover"
    namespace = var.namespace
    labels    = { app = "rover" }
  }

  spec {
    replicas = 1
    selector { match_labels = { app = "rover" } }

    template {
      metadata { labels = { app = "rover" } }
      spec {
        container {
          name  = "rover"
          image = "im2nguyen/rover:latest"
          port { container_port = 9000 }
          
          # In a real setup, we would mount the tfplan/tfstate
          # For now, this serves the UI shell that Traefik routes to
          resources {
            requests = {
              memory = "64Mi"
              cpu    = "50m"
            }
            limits = {
              memory = "128Mi"
              cpu    = "100m"
            }
          }
          volume_mount {
            name       = "src"
            mount_path = "/src/main.tf"
            sub_path   = "main.tf"
          }
        }
        volume {
          name = "src"
          config_map {
            name = kubernetes_config_map.rover_dummy.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "rover" {
  metadata {
    name      = "rover"
    namespace = var.namespace
  }
  spec {
    selector = { app = "rover" }
    port {
      port        = 9000
      target_port = 9000
    }
  }
}
