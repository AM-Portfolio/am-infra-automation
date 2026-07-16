terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
  }
}

# ==============================================================================
# GITHUB RUNNER MODULE — Fully Terraform-Managed (No external runner/ directory)
# ==============================================================================
# All runner image content (Dockerfile + start.sh) is defined inline here.
# Terraform writes the files to the VPS, builds the image, loads it into Kind.
# ==============================================================================

locals {
  runner_dockerfile = file("${path.module}/Dockerfile.runner")
  runner_start_sh   = file("${path.module}/start.sh")
}

# ------------------------------------------------------------------------------
# 1. Namespace
# ------------------------------------------------------------------------------

resource "kubernetes_namespace" "github_actions" {
  metadata {
    name = "github-actions"
    labels = {
      managed-by = "terraform"
    }
  }
}

# ------------------------------------------------------------------------------
# 2. Write Dockerfile + start.sh to VPS and build the image there
# ------------------------------------------------------------------------------

resource "terraform_data" "runner_image" {
  triggers_replace = {
    # Trigger rebuild when the file content changes or environment flips
    dockerfile_hash = sha256(local.runner_dockerfile)
    startsh_hash    = sha256(local.runner_start_sh)
    environment     = var.environment
  }

  # Build logic branched by environment
  provisioner "local-exec" {
    interpreter = ["powershell", "-Command"]
    command     = <<-PS1
      $env = "${var.environment}"
      $modulePath = "${path.module}"
      $rootPath = "${path.cwd}/../../.."
      
      if ($env -eq "local") {
        Write-Host ">>> Building Runner Image LOCALLY for Kind..."
        cd $modulePath
        docker build -t am-infra-gh-runner:latest -f Dockerfile.runner .
        if ($LASTEXITCODE -ne 0) { throw "Docker build failed" }
        
        # Use kind to load. If kind is missing from PATH, fallback to manual import
        if (Get-Command kind -ErrorAction SilentlyContinue) {
          kind load docker-image am-infra-gh-runner:latest --name am-local
        } else {
          Write-Host "Kind not found in PATH, attempting manual container load..."
          docker save am-infra-gh-runner:latest -o runner_image.tar
          docker cp runner_image.tar am-local-control-plane:/tmp/runner_image.tar
          docker exec am-local-control-plane ctr -n k8s.io images import /tmp/runner_image.tar
          Remove-Item runner_image.tar
        }
      } else {
        Write-Host ">>> Building Runner Image on VPS ($env)..."
        # Push files to VPS using the orchestrator
        python "$rootPath/scripts/orchestration/infra.py" push "$modulePath" "/tmp/runner-build"
        if ($LASTEXITCODE -ne 0) { throw "Failed to push files to VPS" }

        # Build on VPS
        python "$rootPath/scripts/orchestration/infra.py" exec "cd /tmp/runner-build && docker build -t am-infra-gh-runner:latest -f Dockerfile.runner ."
        if ($LASTEXITCODE -ne 0) { throw "Remote docker build failed" }
        
        Write-Host "Runner image successfully built on VPS."
      }
    PS1
  }
}


# ------------------------------------------------------------------------------
# 3. Credentials Secret
# ------------------------------------------------------------------------------

resource "kubernetes_secret" "github_runner_secret" {
  metadata {
    name      = "github-runner-secret"
    namespace = kubernetes_namespace.github_actions.metadata[0].name
  }
  type = "Opaque"
  data = {
    REPO_URL     = var.github_repo_url
    GITHUB_PAT   = var.github_pat
    RUNNER_TOKEN = "" # Fetched dynamically by start.sh
  }
  lifecycle {
    ignore_changes = [data["RUNNER_TOKEN"]]
  }
}

# ------------------------------------------------------------------------------
# 4. RBAC
# ------------------------------------------------------------------------------

resource "kubernetes_service_account" "github_runner_sa" {
  metadata {
    name      = "github-runner-sa"
    namespace = kubernetes_namespace.github_actions.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding" "github_runner_binding" {
  metadata {
    name = "github-runner-cluster-admin"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.github_runner_sa.metadata[0].name
    namespace = kubernetes_namespace.github_actions.metadata[0].name
  }
}

# ------------------------------------------------------------------------------
# 5. Deployment
# ------------------------------------------------------------------------------

resource "kubernetes_deployment" "github_runner" {
  depends_on       = [terraform_data.runner_image]
  wait_for_rollout = false

  metadata {
    name      = "github-runner"
    namespace = kubernetes_namespace.github_actions.metadata[0].name
    labels    = { app = "github-runner" }
  }

  spec {
    replicas = 1
    selector { match_labels = { app = "github-runner" } }

    template {
      metadata {
        labels = { app = "github-runner" }
        annotations = {
          "vault.hashicorp.com/agent-inject"                 = "true"
          "vault.hashicorp.com/role"                         = "am-auth-role"
          "vault.hashicorp.com/agent-inject-secret-config"   = "secret/data/am-auth/preprod/master"
          "vault.hashicorp.com/agent-inject-template-config" = <<-EOT
            {{- with secret "secret/data/am-auth/preprod/master" -}}
            {{- range $k, $v := .Data.data -}}
            export {{ $k }}="{{ $v }}"
            {{ end -}}
            {{- end -}}
          EOT
        }
      }

      spec {
        service_account_name = kubernetes_service_account.github_runner_sa.metadata[0].name

        container {
          name              = "runner"
          image             = "am-infra-gh-runner:latest"
          image_pull_policy = "IfNotPresent"
          command           = ["/bin/bash", "/home/github/start.sh"]

          env_from {
            secret_ref {
              name = kubernetes_secret.github_runner_secret.metadata[0].name
            }
          }

          env {
            name  = "RUNNER_SCOPE"
            value = "org"
          }
          env {
            name  = "ORG_NAME"
            value = var.github_org_name
          }

          volume_mount {
            name       = "docker-sock"
            mount_path = "/var/run/docker.sock"
          }

          security_context {
            privileged = true
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
        }

        volume {
          name = "docker-sock"
          host_path { path = "/var/run/docker.sock" }
        }

        node_selector = { tier = "infra" }
      }
    }
  }
}
