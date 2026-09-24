# Phase 3a–3d platform: Keycloak + Argo + Temporal + Lago + P1 UIs (n8n…novu).
# Traefik stays on infra; cross-cluster-http bridges published hosts.

resource "terraform_data" "env_folder_guard" {
  input = local.env
  lifecycle {
    precondition {
      condition     = local.env == "dev"
      error_message = "kind-fleet/dev/platform must set local.env = \"dev\"."
    }
  }
}

module "sizing" {
  source      = "../../../modules/core/platform-sizing"
  environment = local.env
}

module "cluster" {
  source          = "../../../modules/core/cluster"
  env             = local.env
  cluster_role    = "platform"
  api_server_port = 6445
  node_shape      = "one"
}

resource "local_file" "kubeconfig" {
  content         = module.cluster.kubeconfig
  filename        = pathexpand("~/.asrax/kubeconfig.am-dev-platform.yaml")
  file_permission = "0600"
}

data "external" "platform_node_ip" {
  program    = ["PowerShell", "-NoProfile", "-File", "${path.module}/scripts/platform-ip.ps1"]
  depends_on = [module.cluster, local_file.kubeconfig]
}

module "namespaces" {
  source            = "../../../modules/core/namespaces"
  environment       = local.env
  create_identity   = true
  create_apps       = false
  create_github     = false
  create_monitoring = false
  extra_namespaces  = ["argocd", "temporal", "billing", "n8n", "growthbook", "openproject", "am-ai", "notification"]

  depends_on = [module.cluster, local_file.kubeconfig]
}

# Pull Phase 3d images into KinD node containerd (crictl) before Helm/Deploy.
# Do not use host `docker pull` alone — pods run on the kind node, not local Docker.
module "image_preload_3d" {
  source       = "../../../modules/core/kind-image-preload"
  cluster_name = module.cluster.cluster_name
  images = [
    "n8nio/n8n:1.109.2",
    "openproject/openproject:14",
    "ghcr.io/berriai/litellm-database:1.88.1",
    "growthbook/growthbook:4.4.0",
    "langfuse/langfuse:3.100.0",
    "langfuse/langfuse-worker:3.100.0",
    "ghcr.io/novuhq/novu/api:2.1.0",
    "ghcr.io/novuhq/novu/web:2.1.0",
    "ghcr.io/novuhq/novu/worker:2.1.0",
    "ghcr.io/novuhq/novu/ws:2.1.0",
  ]

  depends_on = [module.cluster]
}

module "keycloak" {
  source               = "../../../modules/apps/keycloak"
  environment          = local.env
  root_domain          = local.domain
  namespace            = module.namespaces.identity_ns
  db_host              = "postgres-${local.env}.${local.domain}"
  db_name              = "platform"
  db_user              = "keycloak"
  db_schema            = "keycloak"
  db_password          = var.keycloak_db_password
  node_port            = 30808
  enable_gateway       = true
  gateway_same_cluster = false
  manage_realm         = true
  create_test_users    = true
  mfa_enforce          = false
  otp_optional_enroll  = true
  chart_version        = "25.2.0"
  cpu_request          = module.sizing.keycloak.cpu_request
  cpu_limit            = module.sizing.keycloak.cpu_limit
  memory_request       = module.sizing.keycloak.memory_request
  memory_limit         = module.sizing.keycloak.memory_limit

  depends_on = [module.namespaces, module.sizing]
}

module "argocd" {
  source                     = "../../../modules/apps/argocd"
  environment                = local.env
  root_domain                = local.domain
  namespace                  = "argocd"
  node_port                  = 30443
  enable_gateway             = true
  gateway_same_cluster       = false
  oidc_issuer                = module.keycloak.issuer_url
  oidc_client_secret         = ""
  enable_oidc_secret         = false
  disable_local_admin        = false
  infra_api_server           = "https://127.0.0.1:6443"
  chart_version              = "10.8.0"
  server_cpu_request         = module.sizing.argocd_server.cpu_request
  server_cpu_limit           = module.sizing.argocd_server.cpu_limit
  server_memory_request      = module.sizing.argocd_server.memory_request
  server_memory_limit        = module.sizing.argocd_server.memory_limit
  controller_cpu_request     = module.sizing.argocd_controller.cpu_request
  controller_cpu_limit       = module.sizing.argocd_controller.cpu_limit
  controller_memory_request  = module.sizing.argocd_controller.memory_request
  controller_memory_limit    = module.sizing.argocd_controller.memory_limit
  repo_server_cpu_request    = module.sizing.argocd_repo_server.cpu_request
  repo_server_cpu_limit      = module.sizing.argocd_repo_server.cpu_limit
  repo_server_memory_request = module.sizing.argocd_repo_server.memory_request
  repo_server_memory_limit   = module.sizing.argocd_repo_server.memory_limit

  depends_on = [module.keycloak, module.sizing]
}

# Patch Argo OIDC secret after realm clients exist.
resource "null_resource" "argocd_oidc_patch" {
  triggers = {
    realm = module.keycloak.issuer_url
    hash  = sha256(jsonencode(module.keycloak.oidc_client_secrets))
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    environment = {
      KUBECONFIG = pathexpand("~/.asrax/kubeconfig.am-dev-platform.yaml")
      SECRET     = try(module.keycloak.oidc_client_secrets["argocd"], "")
    }
    command = <<-PS
      if (-not $env:SECRET) { Write-Output 'skip_no_argocd_secret'; exit 0 }
      $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($env:SECRET))
      kubectl -n argocd patch secret argocd-secret --type merge -p "{`"data`":{`"oidc.argocd.clientSecret`":`"$b64`"}}"
      kubectl -n argocd rollout restart deploy/argocd-server
      Write-Output 'argocd_oidc_patched'
    PS
  }

  depends_on = [module.argocd, module.keycloak]
}

# Bridge Keycloak + Argo into infra Traefik (same docker `kind` network).
module "route_auth" {
  source = "../../../modules/core/cross-cluster-http"
  providers = {
    kubernetes = kubernetes.infra
    kubectl    = kubectl.infra
  }
  environment  = local.env
  root_domain  = local.domain
  namespace    = "infra"
  host_label   = "auth"
  service_name = "keycloak-platform"
  service_port = 8080
  backend_host = "am-${local.env}-platform-control-plane"
  backend_ip   = var.platform_node_ip
  backend_port = module.keycloak.node_port

  depends_on = [module.keycloak, data.external.platform_node_ip]
}

module "route_argocd" {
  source = "../../../modules/core/cross-cluster-http"
  providers = {
    kubernetes = kubernetes.infra
    kubectl    = kubectl.infra
  }
  environment  = local.env
  root_domain  = local.domain
  namespace    = "infra"
  host_label   = "argocd"
  service_name = "argocd-platform"
  service_port = 80
  backend_host = "am-${local.env}-platform-control-plane"
  backend_ip   = var.platform_node_ip
  backend_port = module.argocd.node_port

  depends_on = [module.argocd, data.external.platform_node_ip]
}

module "temporal" {
  source                   = "../../../modules/apps/temporal"
  environment              = local.env
  root_domain              = local.domain
  namespace                = "temporal"
  db_host                  = "postgres-${local.env}.${local.domain}"
  db_name                  = "temporal"
  visibility_db_name       = "temporal_visibility"
  db_user                  = "temporal"
  db_password              = var.temporal_db_password
  node_port                = 30823
  enable_gateway           = true
  gateway_same_cluster     = false
  chart_version            = "0.62.0"
  server_cpu_request       = module.sizing.temporal_server.cpu_request
  server_cpu_limit         = module.sizing.temporal_server.cpu_limit
  server_memory_request    = module.sizing.temporal_server.memory_request
  server_memory_limit      = module.sizing.temporal_server.memory_limit
  web_cpu_request          = module.sizing.temporal_web.cpu_request
  web_cpu_limit            = module.sizing.temporal_web.cpu_limit
  web_memory_request       = module.sizing.temporal_web.memory_request
  web_memory_limit         = module.sizing.temporal_web.memory_limit

  depends_on = [module.namespaces, module.sizing, module.keycloak]
}

module "route_temporal" {
  source = "../../../modules/core/cross-cluster-http"
  providers = {
    kubernetes = kubernetes.infra
    kubectl    = kubectl.infra
  }
  environment  = local.env
  root_domain  = local.domain
  namespace    = "infra"
  host_label   = "temporal"
  service_name = "temporal-web-platform"
  service_port = 8080
  backend_host = "am-${local.env}-platform-control-plane"
  backend_ip   = var.platform_node_ip
  backend_port = module.temporal.node_port

  depends_on = [module.temporal, data.external.platform_node_ip]
}

module "lago" {
  source                = "../../../modules/apps/lago"
  environment           = local.env
  root_domain           = local.domain
  namespace             = "billing"
  db_host               = "postgres-${local.env}.${local.domain}"
  db_name               = "lago"
  db_user               = "lago"
  db_schema             = "public"
  db_password           = var.lago_db_password
  redis_host            = "redis-${local.env}.${local.domain}"
  redis_password        = var.redis_password
  redis_db              = 3
  node_port             = 30830
  enable_gateway        = true
  gateway_same_cluster  = false
  chart_version         = "1.28.0"
  api_cpu_request       = module.sizing.lago_api.cpu_request
  api_cpu_limit         = module.sizing.lago_api.cpu_limit
  api_memory_request    = module.sizing.lago_api.memory_request
  api_memory_limit      = module.sizing.lago_api.memory_limit
  front_cpu_request     = module.sizing.lago_front.cpu_request
  front_cpu_limit       = module.sizing.lago_front.cpu_limit
  front_memory_request  = module.sizing.lago_front.memory_request
  front_memory_limit    = module.sizing.lago_front.memory_limit

  depends_on = [module.namespaces, module.sizing, module.keycloak]
}

module "route_lago" {
  source = "../../../modules/core/cross-cluster-http"
  providers = {
    kubernetes = kubernetes.infra
    kubectl    = kubectl.infra
  }
  environment  = local.env
  root_domain  = local.domain
  namespace    = "infra"
  host_label   = "lago"
  service_name = "lago-front-platform"
  service_port = 80
  backend_host = "am-${local.env}-platform-control-plane"
  backend_ip   = var.platform_node_ip
  backend_port = module.lago.node_port

  depends_on = [module.lago, data.external.platform_node_ip]
}

module "n8n" {
  source               = "../../../modules/apps/n8n"
  environment          = local.env
  root_domain          = local.domain
  namespace            = "n8n"
  db_host              = "postgres-${local.env}.${local.domain}"
  db_name              = "platform"
  db_user              = "n8n"
  db_schema            = "n8n"
  db_password          = var.n8n_db_password
  redis_host           = "redis-${local.env}.${local.domain}"
  redis_password       = var.redis_password
  redis_db             = 4
  worker_replicas      = 1
  node_port            = 30567
  enable_gateway       = true
  gateway_same_cluster = false
  image_repository     = "n8nio/n8n"
  image_tag            = "1.109.2"
  cpu_request          = module.sizing.n8n.cpu_request
  cpu_limit            = module.sizing.n8n.cpu_limit
  memory_request       = module.sizing.n8n.memory_request
  memory_limit         = module.sizing.n8n.memory_limit

  depends_on = [module.namespaces, module.sizing, module.keycloak, module.image_preload_3d]
}

module "route_n8n" {
  source = "../../../modules/core/cross-cluster-http"
  providers = {
    kubernetes = kubernetes.infra
    kubectl    = kubectl.infra
  }
  environment  = local.env
  root_domain  = local.domain
  namespace    = "infra"
  host_label   = "n8n"
  service_name = "n8n-platform"
  service_port = 5678
  backend_host = "am-${local.env}-platform-control-plane"
  backend_ip   = var.platform_node_ip
  backend_port = module.n8n.node_port

  depends_on = [module.n8n, data.external.platform_node_ip]
}

module "growthbook" {
  source                   = "../../../modules/apps/growthbook"
  environment              = local.env
  root_domain              = local.domain
  namespace                = "growthbook"
  mongo_host               = "mongo-${local.env}.${local.domain}"
  mongo_db                 = "platform"
  mongo_user               = "growthbook"
  mongo_password           = var.growthbook_mongo_password
  node_port                = 30300
  enable_gateway           = true
  gateway_same_cluster     = false
  frontend_cpu_request     = module.sizing.growthbook_frontend.cpu_request
  frontend_cpu_limit       = module.sizing.growthbook_frontend.cpu_limit
  frontend_memory_request  = module.sizing.growthbook_frontend.memory_request
  frontend_memory_limit    = module.sizing.growthbook_frontend.memory_limit
  backend_cpu_request      = module.sizing.growthbook_backend.cpu_request
  backend_cpu_limit        = module.sizing.growthbook_backend.cpu_limit
  backend_memory_request   = module.sizing.growthbook_backend.memory_request
  backend_memory_limit     = module.sizing.growthbook_backend.memory_limit

  depends_on = [module.namespaces, module.sizing, module.keycloak, module.image_preload_3d]
}

module "route_growthbook" {
  source = "../../../modules/core/cross-cluster-http"
  providers = {
    kubernetes = kubernetes.infra
    kubectl    = kubectl.infra
  }
  environment  = local.env
  root_domain  = local.domain
  namespace    = "infra"
  host_label   = "growthbook"
  service_name = "growthbook-platform"
  service_port = 3000
  backend_host = "am-${local.env}-platform-control-plane"
  backend_ip   = var.platform_node_ip
  backend_port = module.growthbook.node_port

  depends_on = [module.growthbook, data.external.platform_node_ip]
}

module "openproject" {
  source               = "../../../modules/apps/openproject"
  environment          = local.env
  root_domain          = local.domain
  namespace            = "openproject"
  db_host              = "postgres-${local.env}.${local.domain}"
  db_name              = "platform"
  db_user              = "openproject"
  db_schema            = "openproject"
  db_password          = var.openproject_db_password
  node_port            = 30080
  enable_gateway       = true
  gateway_same_cluster = false
  cpu_request          = module.sizing.openproject.cpu_request
  cpu_limit            = module.sizing.openproject.cpu_limit
  memory_request       = module.sizing.openproject.memory_request
  memory_limit         = module.sizing.openproject.memory_limit

  depends_on = [module.namespaces, module.sizing, module.keycloak, module.image_preload_3d]
}

module "route_openproject" {
  source = "../../../modules/core/cross-cluster-http"
  providers = {
    kubernetes = kubernetes.infra
    kubectl    = kubectl.infra
  }
  environment  = local.env
  root_domain  = local.domain
  namespace    = "infra"
  host_label   = "openproject"
  service_name = "openproject-platform"
  service_port = 80
  backend_host = "am-${local.env}-platform-control-plane"
  backend_ip   = var.platform_node_ip
  backend_port = module.openproject.node_port

  depends_on = [module.openproject, data.external.platform_node_ip]
}

module "litellm" {
  source               = "../../../modules/apps/litellm"
  environment          = local.env
  root_domain          = local.domain
  namespace            = "am-ai"
  db_host              = "postgres-${local.env}.${local.domain}"
  db_name              = "platform"
  db_user              = "litellm"
  db_schema            = "litellm"
  db_password          = var.litellm_db_password
  node_port            = 30400
  enable_gateway       = true
  gateway_same_cluster = false
  cpu_request          = module.sizing.litellm.cpu_request
  cpu_limit            = module.sizing.litellm.cpu_limit
  memory_request       = module.sizing.litellm.memory_request
  memory_limit         = module.sizing.litellm.memory_limit

  depends_on = [module.namespaces, module.sizing, module.keycloak, module.image_preload_3d]
}

module "route_litellm" {
  source = "../../../modules/core/cross-cluster-http"
  providers = {
    kubernetes = kubernetes.infra
    kubectl    = kubectl.infra
  }
  environment  = local.env
  root_domain  = local.domain
  namespace    = "infra"
  host_label   = "litellm"
  service_name = "litellm-platform"
  service_port = 4000
  backend_host = "am-${local.env}-platform-control-plane"
  backend_ip   = var.platform_node_ip
  backend_port = module.litellm.node_port

  depends_on = [module.litellm, data.external.platform_node_ip]
}

module "langfuse" {
  source                      = "../../../modules/apps/langfuse"
  environment                 = local.env
  root_domain                 = local.domain
  namespace                   = "am-ai"
  db_host                     = "postgres-${local.env}.${local.domain}"
  db_name                     = "platform"
  db_user                     = "langfuse"
  db_schema                   = "langfuse"
  db_password                 = var.langfuse_db_password
  redis_host                  = "redis-${local.env}.${local.domain}"
  redis_password              = var.redis_password
  redis_db                    = 0
  minio_endpoint              = "minio-${local.env}.${local.domain}:9000"
  minio_user                  = "langfuse"
  minio_password              = var.langfuse_minio_password
  minio_bucket                = "platform"
  node_port                   = 30301
  enable_gateway              = true
  gateway_same_cluster        = false
  web_cpu_request             = module.sizing.langfuse_web.cpu_request
  web_cpu_limit               = module.sizing.langfuse_web.cpu_limit
  web_memory_request          = module.sizing.langfuse_web.memory_request
  web_memory_limit            = module.sizing.langfuse_web.memory_limit
  clickhouse_cpu_request      = module.sizing.langfuse_clickhouse.cpu_request
  clickhouse_cpu_limit        = module.sizing.langfuse_clickhouse.cpu_limit
  clickhouse_memory_request   = module.sizing.langfuse_clickhouse.memory_request
  clickhouse_memory_limit     = module.sizing.langfuse_clickhouse.memory_limit

  depends_on = [module.namespaces, module.sizing, module.keycloak, module.image_preload_3d]
}

module "route_langfuse" {
  source = "../../../modules/core/cross-cluster-http"
  providers = {
    kubernetes = kubernetes.infra
    kubectl    = kubectl.infra
  }
  environment  = local.env
  root_domain  = local.domain
  namespace    = "infra"
  host_label   = "langfuse"
  service_name = "langfuse-platform"
  service_port = 3000
  backend_host = "am-${local.env}-platform-control-plane"
  backend_ip   = var.platform_node_ip
  backend_port = module.langfuse.node_port

  depends_on = [module.langfuse, data.external.platform_node_ip]
}

module "novu" {
  source                 = "../../../modules/apps/novu"
  environment            = local.env
  root_domain            = local.domain
  namespace              = "notification"
  chart_path             = abspath("${path.module}/../../../../../am-platform/automation/helm/novu")
  mongo_host             = "mongo-${local.env}.${local.domain}"
  mongo_db               = "novu"
  mongo_user             = "admin"
  mongo_password         = var.mongo_admin_password
  redis_host             = "redis-${local.env}.${local.domain}"
  redis_password         = var.redis_password
  node_port              = 30420
  enable_gateway         = true
  gateway_same_cluster   = false
  api_cpu_request        = module.sizing.novu_api.cpu_request
  api_cpu_limit          = module.sizing.novu_api.cpu_limit
  api_memory_request     = module.sizing.novu_api.memory_request
  api_memory_limit       = module.sizing.novu_api.memory_limit
  worker_cpu_request     = module.sizing.novu_worker.cpu_request
  worker_cpu_limit       = module.sizing.novu_worker.cpu_limit
  worker_memory_request  = module.sizing.novu_worker.memory_request
  worker_memory_limit    = module.sizing.novu_worker.memory_limit
  web_cpu_request        = module.sizing.novu_web.cpu_request
  web_cpu_limit          = module.sizing.novu_web.cpu_limit
  web_memory_request     = module.sizing.novu_web.memory_request
  web_memory_limit       = module.sizing.novu_web.memory_limit
  ws_cpu_request         = module.sizing.novu_ws.cpu_request
  ws_cpu_limit           = module.sizing.novu_ws.cpu_limit
  ws_memory_request      = module.sizing.novu_ws.memory_request
  ws_memory_limit        = module.sizing.novu_ws.memory_limit

  depends_on = [module.namespaces, module.sizing, module.keycloak, module.image_preload_3d]
}

module "route_novu" {
  source = "../../../modules/core/cross-cluster-http"
  providers = {
    kubernetes = kubernetes.infra
    kubectl    = kubectl.infra
  }
  environment  = local.env
  root_domain  = local.domain
  namespace    = "infra"
  host_label   = "novu"
  service_name = "novu-web-platform"
  service_port = 4200
  backend_host = "am-${local.env}-platform-control-plane"
  backend_ip   = var.platform_node_ip
  backend_port = module.novu.node_port

  depends_on = [module.novu, data.external.platform_node_ip]
}

# Persist OIDC secrets into Vault KV (names only path under apps/data/dev/oidc).
resource "null_resource" "vault_oidc_secrets" {
  count = var.vault_addr != "" ? 1 : 0

  triggers = {
    secrets = sha256(jsonencode(module.keycloak.oidc_client_secrets))
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    environment = {
      VAULT_ADDR   = var.vault_addr
      VAULT_TOKEN  = var.vault_token
      SECRETS_JSON = jsonencode(module.keycloak.oidc_client_secrets)
    }
    command = <<-PS
      $ErrorActionPreference = 'Stop'
      if (-not $env:VAULT_TOKEN) { Write-Output 'skip_vault_no_token'; exit 0 }
      $map = $env:SECRETS_JSON | ConvertFrom-Json
      foreach ($p in $map.PSObject.Properties) {
        $path = "apps/data/dev/oidc/$($p.Name)"
        $body = @{ data = @{ data = @{ client_id = $p.Name; client_secret = $p.Value } } } | ConvertTo-Json -Depth 5
        try {
          Invoke-RestMethod -Method Post -Uri "$($env:VAULT_ADDR)/v1/$path" -Headers @{ 'X-Vault-Token' = $env:VAULT_TOKEN } -ContentType 'application/json' -Body $body | Out-Null
          Write-Output "vault_ok=$path"
        } catch {
          Write-Output "vault_warn=$path err=$($_.Exception.Message)"
        }
      }
    PS
  }

  depends_on = [module.keycloak]
}

# Test user passwords → Vault (usernames documented in TODO; never commit passwords).
resource "null_resource" "vault_test_users" {
  count = var.vault_addr != "" ? 1 : 0

  triggers = {
    users = sha256(jsonencode(module.keycloak.test_user_passwords))
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    environment = {
      VAULT_ADDR  = var.vault_addr
      VAULT_TOKEN = var.vault_token
      USERS_JSON  = jsonencode(module.keycloak.test_user_passwords)
    }
    command = <<-PS
      $ErrorActionPreference = 'Stop'
      if (-not $env:VAULT_TOKEN) { Write-Output 'skip_vault_no_token'; exit 0 }
      $map = $env:USERS_JSON | ConvertFrom-Json
      $data = @{}
      foreach ($p in $map.PSObject.Properties) { $data[$p.Name] = $p.Value }
      $path = "apps/data/dev/infra/keycloak-test-users"
      $body = @{ data = @{ data = $data } } | ConvertTo-Json -Depth 5
      try {
        Invoke-RestMethod -Method Post -Uri "$($env:VAULT_ADDR)/v1/$path" -Headers @{ 'X-Vault-Token' = $env:VAULT_TOKEN } -ContentType 'application/json' -Body $body | Out-Null
        Write-Output "vault_ok=$path"
      } catch {
        Write-Output "vault_warn=$path err=$($_.Exception.Message)"
      }
    PS
  }

  depends_on = [module.keycloak]
}

output "cluster_name" { value = module.cluster.cluster_name }
output "api_server_port" { value = module.cluster.api_server_port }
output "auth_host" { value = module.keycloak.auth_host }
output "argocd_host" { value = module.argocd.argocd_host }
output "temporal_host" { value = module.temporal.ui_host }
output "lago_host" { value = module.lago.ui_host }
output "n8n_host" { value = module.n8n.ui_host }
output "growthbook_host" { value = module.growthbook.ui_host }
output "openproject_host" { value = module.openproject.ui_host }
output "litellm_host" { value = module.litellm.ui_host }
output "langfuse_host" { value = module.langfuse.ui_host }
output "novu_host" { value = module.novu.ui_host }
output "issuer_url" { value = module.keycloak.issuer_url }
output "keycloak_admin_password" {
  value     = module.keycloak.admin_password
  sensitive = true
}
output "argocd_admin_password" {
  value     = module.argocd.admin_password
  sensitive = true
}
