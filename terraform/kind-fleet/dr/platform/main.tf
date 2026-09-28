# Phase 3a–3d platform (dr): Keycloak + Argo + Temporal + Lago + P1 UIs.
# identity-infra-split Phase 6: set co_locate_on_infra=true → am-dr-infra (no platform Kind).
# Default false keeps am-dr-platform :6445 until soak apply.
# Apply on VPS3 only. State: /data/am-state/terraform/dr/platform/

resource "terraform_data" "env_folder_guard" {
  input = local.env
  lifecycle {
    precondition {
      condition     = local.env == "dr"
      error_message = "kind-fleet/dr/platform must set local.env = \"dr\"."
    }
  }
}

module "sizing" {
  source      = "../../../modules/core/platform-sizing"
  environment = local.env
}

module "cluster" {
  count              = local.co_locate_on_infra ? 0 : 1
  source             = "../../../modules/core/cluster"
  env                = local.env
  cluster_role       = "platform"
  node_shape         = "one"
  vps_ram_gb         = 32
  api_server_address = "0.0.0.0"
  vps_ip             = "129.121.128.131"
  config_output_path = "/data/am-state/kubeconfig.am-dr-platform.yaml"
}

resource "null_resource" "kubeconfig_asrax" {
  count = local.co_locate_on_infra ? 0 : 1
  triggers = {
    cluster  = module.cluster[0].cluster_name
    endpoint = module.cluster[0].endpoint
  }
  provisioner "local-exec" {
    command = "mkdir -p /home/am-ops/.asrax && cp -f /data/am-state/kubeconfig.am-dr-platform.yaml /home/am-ops/.asrax/kubeconfig.am-dr-platform.yaml && chmod 600 /home/am-ops/.asrax/kubeconfig.am-dr-platform.yaml && chown am-ops:am-ops /home/am-ops/.asrax/kubeconfig.am-dr-platform.yaml || true"
  }
  depends_on = [module.cluster]
}

data "external" "platform_node_ip" {
  count      = local.co_locate_on_infra ? 0 : 1
  program    = ["bash", "${path.module}/scripts/platform-ip.sh"]
  depends_on = [module.cluster]
}

resource "terraform_data" "kind_ready" {
  input = local.co_locate_on_infra ? "am-dr-infra" : module.cluster[0].cluster_name
}

locals {
  platform_ip = local.co_locate_on_infra ? "" : coalesce(var.platform_node_ip, try(data.external.platform_node_ip[0].result.ip, ""))
  kind_name   = local.co_locate_on_infra ? "am-dr-infra" : module.cluster[0].cluster_name
  # DR store hosts (Phase 2 exposer / DNS-only grey-cloud).
  pg_host    = "postgres-dr.${local.domain}"
  mongo_host = "mongodb-dr.${local.domain}"
  redis_host = "redis-dr.${local.domain}"
  minio_host = "minio-dr.${local.domain}:9000"
}

module "namespaces" {
  source            = "../../../modules/core/namespaces"
  environment       = local.env
  create_identity   = true
  create_apps       = false
  create_github     = false
  create_monitoring = false
  extra_namespaces  = ["argocd", "temporal", "billing", "n8n", "growthbook", "openproject", "am-ai", "notification"]

  depends_on = [terraform_data.kind_ready]
}

module "image_preload_3d" {
  source       = "../../../modules/core/kind-image-preload"
  cluster_name = local.kind_name
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

  depends_on = [terraform_data.kind_ready]
}

module "keycloak" {
  source               = "../../../modules/apps/keycloak"
  environment          = local.env
  root_domain          = local.domain
  namespace            = module.namespaces.identity_ns
  db_host              = local.pg_host
  db_name              = "platform"
  db_user              = "keycloak"
  db_schema            = "keycloak"
  db_password          = var.keycloak_db_password
  node_port            = 30808
  enable_gateway       = true
  gateway_same_cluster = local.gateway_same_cluster
  # DR-primary CF LB: same issuer host as Contabo (auth.asrax.in); keep auth-dr for drills.
  public_hostname      = "auth.${local.domain}"
  also_match_env_host  = true
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
  gateway_same_cluster       = local.gateway_same_cluster
  oidc_issuer                = module.keycloak.issuer_url
  oidc_client_secret         = ""
  enable_oidc_secret         = false
  disable_local_admin        = false
  infra_api_server           = "https://129.121.128.131:6443"
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

resource "null_resource" "argocd_oidc_patch" {
  triggers = {
    realm = module.keycloak.issuer_url
    hash  = sha256(jsonencode(module.keycloak.oidc_client_secrets))
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = local.workload_kubeconfig
      SECRET     = try(module.keycloak.oidc_client_secrets["argocd"], "")
    }
    command = <<-BASH
      set -euo pipefail
      if [ -z "$${SECRET}" ]; then echo skip_no_argocd_secret; exit 0; fi
      B64=$(printf '%s' "$${SECRET}" | base64 -w0)
      kubectl -n argocd patch secret argocd-secret --type merge -p "{\"data\":{\"oidc.argocd.clientSecret\":\"$${B64}\"}}"
      kubectl -n argocd rollout restart deploy/argocd-server
      echo argocd_oidc_patched
    BASH
  }

  depends_on = [module.argocd, module.keycloak]
}

module "route_auth" {
  source = "../../../modules/core/cross-cluster-http"
  count  = local.cross_cluster_routes ? 1 : 0
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
  backend_ip   = local.platform_ip
  backend_port = module.keycloak.node_port

  depends_on = [module.keycloak]
}

module "route_argocd" {
  source = "../../../modules/core/cross-cluster-http"
  count  = local.cross_cluster_routes ? 1 : 0
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
  backend_ip   = local.platform_ip
  backend_port = module.argocd.node_port

  depends_on = [module.argocd]
}

module "temporal" {
  source                = "../../../modules/apps/temporal"
  environment           = local.env
  root_domain           = local.domain
  namespace             = "temporal"
  db_host               = local.pg_host
  db_name               = "temporal"
  visibility_db_name    = "temporal_visibility"
  db_user               = "temporal"
  db_password           = var.temporal_db_password
  node_port             = 30823
  enable_gateway        = true
  gateway_same_cluster  = local.gateway_same_cluster
  chart_version         = "0.62.0"
  server_cpu_request    = module.sizing.temporal_server.cpu_request
  server_cpu_limit      = module.sizing.temporal_server.cpu_limit
  server_memory_request = module.sizing.temporal_server.memory_request
  server_memory_limit   = module.sizing.temporal_server.memory_limit
  web_cpu_request       = module.sizing.temporal_web.cpu_request
  web_cpu_limit         = module.sizing.temporal_web.cpu_limit
  web_memory_request    = module.sizing.temporal_web.memory_request
  web_memory_limit      = module.sizing.temporal_web.memory_limit

  depends_on = [module.namespaces, module.sizing, module.keycloak]
}

module "route_temporal" {
  source = "../../../modules/core/cross-cluster-http"
  count  = local.cross_cluster_routes ? 1 : 0
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
  backend_ip   = local.platform_ip
  backend_port = module.temporal.node_port

  depends_on = [module.temporal]
}

module "lago" {
  source               = "../../../modules/apps/lago"
  environment          = local.env
  root_domain          = local.domain
  namespace            = "billing"
  db_host              = local.pg_host
  db_name              = "lago"
  db_user              = "lago"
  db_schema            = "public"
  db_password          = var.lago_db_password
  redis_host           = local.redis_host
  redis_password       = var.redis_password
  redis_db             = 3
  node_port            = 30830
  enable_gateway       = true
  gateway_same_cluster = local.gateway_same_cluster
  chart_version        = "1.28.0"
  api_cpu_request      = module.sizing.lago_api.cpu_request
  api_cpu_limit        = module.sizing.lago_api.cpu_limit
  api_memory_request   = module.sizing.lago_api.memory_request
  api_memory_limit     = module.sizing.lago_api.memory_limit
  front_cpu_request    = module.sizing.lago_front.cpu_request
  front_cpu_limit      = module.sizing.lago_front.cpu_limit
  front_memory_request = module.sizing.lago_front.memory_request
  front_memory_limit   = module.sizing.lago_front.memory_limit

  depends_on = [module.namespaces, module.sizing, module.keycloak]
}

module "route_lago" {
  source = "../../../modules/core/cross-cluster-http"
  count  = local.cross_cluster_routes ? 1 : 0
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
  backend_ip   = local.platform_ip
  backend_port = module.lago.node_port

  depends_on = [module.lago]
}

module "n8n" {
  source               = "../../../modules/apps/n8n"
  environment          = local.env
  root_domain          = local.domain
  namespace            = "n8n"
  db_host              = local.pg_host
  db_name              = "platform"
  db_user              = "n8n"
  db_schema            = "n8n"
  db_password          = var.n8n_db_password
  redis_host           = local.redis_host
  redis_password       = var.redis_password
  redis_db             = 4
  worker_replicas      = 1
  node_port            = 30567
  enable_gateway       = true
  gateway_same_cluster = local.gateway_same_cluster
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
  count  = local.cross_cluster_routes ? 1 : 0
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
  backend_ip   = local.platform_ip
  backend_port = module.n8n.node_port

  depends_on = [module.n8n]
}

module "growthbook" {
  source                  = "../../../modules/apps/growthbook"
  environment             = local.env
  root_domain             = local.domain
  namespace               = "growthbook"
  mongo_host              = local.mongo_host
  mongo_db                = "platform"
  mongo_user              = "growthbook"
  mongo_password          = var.growthbook_mongo_password
  node_port               = 30300
  enable_gateway          = true
  gateway_same_cluster    = local.gateway_same_cluster
  frontend_cpu_request    = module.sizing.growthbook_frontend.cpu_request
  frontend_cpu_limit      = module.sizing.growthbook_frontend.cpu_limit
  frontend_memory_request = module.sizing.growthbook_frontend.memory_request
  frontend_memory_limit   = module.sizing.growthbook_frontend.memory_limit
  backend_cpu_request     = module.sizing.growthbook_backend.cpu_request
  backend_cpu_limit       = module.sizing.growthbook_backend.cpu_limit
  backend_memory_request  = module.sizing.growthbook_backend.memory_request
  backend_memory_limit    = module.sizing.growthbook_backend.memory_limit

  depends_on = [module.namespaces, module.sizing, module.keycloak, module.image_preload_3d]
}

module "route_growthbook" {
  source = "../../../modules/core/cross-cluster-http"
  count  = local.cross_cluster_routes ? 1 : 0
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
  backend_ip   = local.platform_ip
  backend_port = module.growthbook.node_port

  depends_on = [module.growthbook]
}

module "openproject" {
  source               = "../../../modules/apps/openproject"
  environment          = local.env
  root_domain          = local.domain
  namespace            = "openproject"
  db_host              = local.pg_host
  db_name              = "platform"
  db_user              = "openproject"
  db_schema            = "openproject"
  db_password          = var.openproject_db_password
  node_port            = 30080
  enable_gateway       = true
  gateway_same_cluster = local.gateway_same_cluster
  cpu_request          = module.sizing.openproject.cpu_request
  cpu_limit            = module.sizing.openproject.cpu_limit
  memory_request       = module.sizing.openproject.memory_request
  memory_limit         = module.sizing.openproject.memory_limit

  depends_on = [module.namespaces, module.sizing, module.keycloak, module.image_preload_3d]
}

module "route_openproject" {
  source = "../../../modules/core/cross-cluster-http"
  count  = local.cross_cluster_routes ? 1 : 0
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
  backend_ip   = local.platform_ip
  backend_port = module.openproject.node_port

  depends_on = [module.openproject]
}

module "litellm" {
  source               = "../../../modules/apps/litellm"
  environment          = local.env
  root_domain          = local.domain
  namespace            = "am-ai"
  db_host              = local.pg_host
  db_name              = "platform"
  db_user              = "litellm"
  db_schema            = "litellm"
  db_password          = var.litellm_db_password
  node_port            = 30400
  enable_gateway       = true
  gateway_same_cluster = local.gateway_same_cluster
  cpu_request          = module.sizing.litellm.cpu_request
  cpu_limit            = module.sizing.litellm.cpu_limit
  memory_request       = module.sizing.litellm.memory_request
  memory_limit         = module.sizing.litellm.memory_limit

  depends_on = [module.namespaces, module.sizing, module.keycloak, module.image_preload_3d]
}

module "route_litellm" {
  source = "../../../modules/core/cross-cluster-http"
  count  = local.cross_cluster_routes ? 1 : 0
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
  backend_ip   = local.platform_ip
  backend_port = module.litellm.node_port

  depends_on = [module.litellm]
}

module "langfuse" {
  source                    = "../../../modules/apps/langfuse"
  environment               = local.env
  root_domain               = local.domain
  namespace                 = "am-ai"
  db_host                   = local.pg_host
  db_name                   = "platform"
  db_user                   = "langfuse"
  db_schema                 = "langfuse"
  db_password               = var.langfuse_db_password
  redis_host                = local.redis_host
  redis_password            = var.redis_password
  redis_db                  = 0
  minio_endpoint            = local.minio_host
  minio_user                = "langfuse"
  minio_password            = var.langfuse_minio_password
  minio_bucket              = "platform"
  node_port                 = 30301
  enable_gateway            = true
  gateway_same_cluster      = local.gateway_same_cluster
  web_cpu_request           = module.sizing.langfuse_web.cpu_request
  web_cpu_limit             = module.sizing.langfuse_web.cpu_limit
  web_memory_request        = module.sizing.langfuse_web.memory_request
  web_memory_limit          = module.sizing.langfuse_web.memory_limit
  clickhouse_cpu_request    = module.sizing.langfuse_clickhouse.cpu_request
  clickhouse_cpu_limit      = module.sizing.langfuse_clickhouse.cpu_limit
  clickhouse_memory_request = module.sizing.langfuse_clickhouse.memory_request
  clickhouse_memory_limit   = module.sizing.langfuse_clickhouse.memory_limit

  depends_on = [module.namespaces, module.sizing, module.keycloak, module.image_preload_3d]
}

module "route_langfuse" {
  source = "../../../modules/core/cross-cluster-http"
  count  = local.cross_cluster_routes ? 1 : 0
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
  backend_ip   = local.platform_ip
  backend_port = module.langfuse.node_port

  depends_on = [module.langfuse]
}

module "novu" {
  source                = "../../../modules/apps/novu"
  environment           = local.env
  root_domain           = local.domain
  namespace             = "notification"
  chart_path            = "/home/am-ops/src/am-platform/automation/helm/novu"
  mongo_host            = local.mongo_host
  mongo_db              = "novu"
  mongo_user            = "admin"
  mongo_password        = var.mongo_admin_password
  redis_host            = local.redis_host
  redis_password        = var.redis_password
  node_port             = 30420
  enable_gateway        = true
  gateway_same_cluster  = local.gateway_same_cluster
  api_cpu_request       = module.sizing.novu_api.cpu_request
  api_cpu_limit         = module.sizing.novu_api.cpu_limit
  api_memory_request    = module.sizing.novu_api.memory_request
  api_memory_limit      = module.sizing.novu_api.memory_limit
  worker_cpu_request    = module.sizing.novu_worker.cpu_request
  worker_cpu_limit      = module.sizing.novu_worker.cpu_limit
  worker_memory_request = module.sizing.novu_worker.memory_request
  worker_memory_limit   = module.sizing.novu_worker.memory_limit
  web_cpu_request       = module.sizing.novu_web.cpu_request
  web_cpu_limit         = module.sizing.novu_web.cpu_limit
  web_memory_request    = module.sizing.novu_web.memory_request
  web_memory_limit      = module.sizing.novu_web.memory_limit
  ws_cpu_request        = module.sizing.novu_ws.cpu_request
  ws_cpu_limit          = module.sizing.novu_ws.cpu_limit
  ws_memory_request     = module.sizing.novu_ws.memory_request
  ws_memory_limit       = module.sizing.novu_ws.memory_limit

  depends_on = [module.namespaces, module.sizing, module.keycloak, module.image_preload_3d]
}

module "route_novu" {
  source = "../../../modules/core/cross-cluster-http"
  count  = local.cross_cluster_routes ? 1 : 0
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
  backend_ip   = local.platform_ip
  backend_port = module.novu.node_port

  depends_on = [module.novu]
}

resource "null_resource" "vault_oidc_secrets" {
  count = var.vault_token != "" ? 1 : 0

  triggers = {
    secrets = sha256(jsonencode(module.keycloak.oidc_client_secrets))
    env     = local.env
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      VAULT_ADDR   = var.vault_addr
      VAULT_TOKEN  = var.vault_token
      FLEET_ENV    = local.env
      ISSUER_URL   = module.keycloak.issuer_url
      SECRETS_JSON = jsonencode(module.keycloak.oidc_client_secrets)
      OIDC_ENV     = "/data/am-state/credentials/${local.env}/oidc.env"
    }
    command = <<-BASH
      set -euo pipefail
      mkdir -p "$(dirname "$OIDC_ENV")"
      umask 077
      python3 - <<'PY'
import json, os, urllib.request
addr = os.environ["VAULT_ADDR"].rstrip("/")
token = os.environ["VAULT_TOKEN"]
env = os.environ["FLEET_ENV"]
issuer = os.environ["ISSUER_URL"]
secrets = json.loads(os.environ["SECRETS_JSON"])
oidc_path = os.environ["OIDC_ENV"]
lines = [f"# OIDC clients for {env}. Not for git.", f"ISSUER_URL={issuer}"]
for name, secret in secrets.items():
    path = f"apps/data/{env}/oidc/{name}"
    body = json.dumps({"data": {"client_id": name, "client_secret": secret, "issuer_url": issuer}}).encode()
    req = urllib.request.Request(f"{addr}/v1/{path}", data=body, method="POST",
        headers={"X-Vault-Token": token, "Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req, timeout=30)
        print(f"vault_ok={path}")
    except Exception as e:
        print(f"vault_warn={path} err={e}")
        raise
    safe = name.upper().replace("-", "_").replace(".", "_")
    lines.append(f"OIDC_{safe}_CLIENT_ID={name}")
    lines.append(f"OIDC_{safe}_CLIENT_SECRET={secret}")
with open(oidc_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
print(f"wrote {oidc_path}")
PY
    BASH
  }

  depends_on = [module.keycloak]
}

resource "null_resource" "write_keycloak_admin_env" {
  triggers = {
    admin_pw   = sha256(module.keycloak.admin_password)
    admin_user = module.keycloak.admin_user
    env        = local.env
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KC_ADMIN_USER = module.keycloak.admin_user
      KC_ADMIN_PASS = module.keycloak.admin_password
      KC_REALM      = "am-realm"
      KC_ISSUER     = module.keycloak.issuer_url
      KC_AUTH_HOST  = module.keycloak.auth_host
      FLEET_ENV     = local.env
      OUT_FILE      = "/data/am-state/credentials/${local.env}/keycloak-admin.env"
      COMPAT_LINK   = "/data/am-state/credentials/${local.env}-keycloak-admin.env"
    }
    command = <<-BASH
      set -euo pipefail
      mkdir -p "$(dirname "$OUT_FILE")"
      umask 077
      cat > "$OUT_FILE" <<EOF
KEYCLOAK_ADMIN_USER=$KC_ADMIN_USER
KEYCLOAK_ADMIN_PASSWORD=$KC_ADMIN_PASS
KEYCLOAK_REALM=$KC_REALM
KEYCLOAK_URL=https://$KC_AUTH_HOST
ISSUER_URL=$KC_ISSUER
FLEET_ENV=$FLEET_ENV
EOF
      ln -sfn "$OUT_FILE" "$COMPAT_LINK"
      echo "wrote $OUT_FILE (compat $COMPAT_LINK)"
    BASH
  }

  depends_on = [module.keycloak]
}

resource "null_resource" "write_argocd_admin_env" {
  triggers = {
    admin_pw = sha256(module.argocd.admin_password)
    env      = local.env
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      ARGO_PASS = module.argocd.admin_password
      ARGO_HOST = module.argocd.argocd_host
      FLEET_ENV = local.env
      OUT_FILE  = "/data/am-state/credentials/${local.env}/argocd-admin.env"
    }
    command = <<-BASH
      set -euo pipefail
      mkdir -p "$(dirname "$OUT_FILE")"
      umask 077
      cat > "$OUT_FILE" <<EOF
ARGOCD_ADMIN_USER=admin
ARGOCD_ADMIN_PASSWORD=$ARGO_PASS
ARGOCD_HOST=https://$ARGO_HOST
FLEET_ENV=$FLEET_ENV
EOF
      echo "wrote $OUT_FILE"
    BASH
  }

  depends_on = [module.argocd]
}

resource "null_resource" "vault_test_users" {
  count = var.vault_token != "" ? 1 : 0

  triggers = {
    users = sha256(jsonencode(module.keycloak.test_user_passwords))
    env   = local.env
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      VAULT_ADDR  = var.vault_addr
      VAULT_TOKEN = var.vault_token
      FLEET_ENV   = local.env
      USERS_JSON  = jsonencode(module.keycloak.test_user_passwords)
      SSO_ENV     = "/data/am-state/credentials/${local.env}/sso-test-users.env"
    }
    command = <<-BASH
      set -euo pipefail
      mkdir -p "$(dirname "$SSO_ENV")"
      umask 077
      python3 - <<'PY'
import json, os, urllib.request
addr = os.environ["VAULT_ADDR"].rstrip("/")
token = os.environ["VAULT_TOKEN"]
env = os.environ["FLEET_ENV"]
users = json.loads(os.environ["USERS_JSON"])
sso_path = os.environ["SSO_ENV"]
path = f"apps/data/{env}/infra/keycloak-test-users"
# KV v2 write body is {"data": <secret map>} — do not double-nest.
secret = dict(users)
lines = [f"# SSO test users for {env}. Not for git."]
if "am-admin-test" in users:
    secret.setdefault("admin_username", "am-admin-test")
    secret.setdefault("admin_password", users["am-admin-test"])
    secret.setdefault("AM_ADMIN_TEST_USERNAME", "am-admin-test")
    secret.setdefault("AM_ADMIN_TEST_PASSWORD", users["am-admin-test"])
    lines.append("AM_ADMIN_TEST_USERNAME=am-admin-test")
    lines.append(f"AM_ADMIN_TEST_PASSWORD={users['am-admin-test']}")
if "am-user-test" in users:
    secret.setdefault("user_username", "am-user-test")
    secret.setdefault("user_password", users["am-user-test"])
    secret.setdefault("AM_USER_TEST_USERNAME", "am-user-test")
    secret.setdefault("AM_USER_TEST_PASSWORD", users["am-user-test"])
    lines.append("AM_USER_TEST_USERNAME=am-user-test")
    lines.append(f"AM_USER_TEST_PASSWORD={users['am-user-test']}")
body = json.dumps({"data": secret}).encode()
req = urllib.request.Request(f"{addr}/v1/{path}", data=body, method="POST",
    headers={"X-Vault-Token": token, "Content-Type": "application/json"})
try:
    urllib.request.urlopen(req, timeout=30)
    print(f"vault_ok={path}")
except Exception as e:
    print(f"vault_warn={path} err={e}")
    raise
with open(sso_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
print(f"wrote {sso_path}")
PY
    BASH
  }

  depends_on = [module.keycloak]
}

resource "null_resource" "credentials_readme" {
  triggers = {
    env = local.env
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      FLEET_ENV = local.env
      CREDS_DIR = "/data/am-state/credentials/${local.env}"
    }
    command = <<-BASH
      set -euo pipefail
      mkdir -p "$CREDS_DIR"
      cat > "$CREDS_DIR/README.txt" <<EOF
AM fleet credentials for env=$FLEET_ENV (host SoT under /data/am-state/credentials/$FLEET_ENV/).
Files: keycloak-admin.env, infra-stores.env, oidc.env, sso-test-users.env, argocd-admin.env, vault-root.env
Compat symlinks: /data/am-state/credentials/$FLEET_ENV-keycloak-admin.env, $FLEET_ENV-infra-stores.env
Vault mirror: apps/data/$FLEET_ENV/oidc/* and apps/data/$FLEET_ENV/infra/keycloak-test-users
Never commit these files. Mode 600/700.
EOF
      chmod 700 "$CREDS_DIR" || true
      echo "wrote $CREDS_DIR/README.txt"
    BASH
  }
}

output "cluster_name" { value = local.kind_name }
output "api_server_port" { value = local.co_locate_on_infra ? 6443 : try(module.cluster[0].api_server_port, 6445) }
output "co_locate_on_infra" { value = local.co_locate_on_infra }
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
output "platform_node_ip" { value = local.platform_ip }
