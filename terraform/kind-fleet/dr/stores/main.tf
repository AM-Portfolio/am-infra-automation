# DR stores — adapted from kind-fleet/prod/stores. Apply on VPS3 only.
# Vault: injector off, watcher on, unsealer off. enable_gateway=true (2E IngressRoutes).
# environment=dr sizing (32 GB class). Keys SoT: /data/am-state/vault-dr-infra.json

resource "terraform_data" "env_folder_guard" {
  input = local.env
  lifecycle {
    precondition {
      condition     = local.env == "dr"
      error_message = "kind-fleet/dr/stores must set local.env = \"dr\". Do not apply DR sizes on the laptop."
    }
  }
}

module "sizing" {
  source      = "../../../modules/core/store-sizing"
  environment = local.env
}

resource "kubernetes_storage_class_v1" "manual_hostpath" {
  metadata { name = "manual-hostpath" }
  storage_provisioner    = "kubernetes.io/no-provisioner"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = false
}

module "namespaces" {
  source            = "../../../modules/core/namespaces"
  environment       = local.env
  create_identity   = false
  create_apps       = false
  create_github     = false
  create_monitoring = false
  extra_namespaces  = []
}

module "postgresql" {
  source           = "../../../modules/apps/postgresql"
  root_domain      = local.domain
  namespace        = module.namespaces.infra_ns
  environment      = local.env
  db_password      = random_password.postgres.result
  pgadmin_password = random_password.postgres.result
  oidc_enabled     = false
  enable_gateway   = true
  cpu_request      = module.sizing.postgresql.cpu_request
  cpu_limit        = module.sizing.postgresql.cpu_limit
  memory_request   = module.sizing.postgresql.memory_request
  memory_limit     = module.sizing.postgresql.memory_limit
  storage          = module.sizing.postgresql.storage
}

module "mongodb" {
  source              = "../../../modules/apps/mongodb"
  root_domain         = local.domain
  namespace           = module.namespaces.infra_ns
  environment         = local.env
  mongo_root_user     = "admin"
  mongo_root_password = random_password.mongo.result
  oidc_enabled        = false
  enable_gateway      = true
  cpu_request         = module.sizing.mongodb.cpu_request
  cpu_limit           = module.sizing.mongodb.cpu_limit
  memory_request      = module.sizing.mongodb.memory_request
  memory_limit        = module.sizing.mongodb.memory_limit
  storage             = module.sizing.mongodb.storage
}

module "redis" {
  source          = "../../../modules/apps/redis"
  root_domain     = local.domain
  namespace       = module.namespaces.infra_ns
  environment     = local.env
  redis_password  = random_password.redis.result
  oidc_enabled    = false
  enable_gateway  = true
  cpu_request     = module.sizing.redis.cpu_request
  cpu_limit       = module.sizing.redis.cpu_limit
  memory_request  = module.sizing.redis.memory_request
  memory_limit    = module.sizing.redis.memory_limit
  storage         = module.sizing.redis.storage
  redis_maxmemory = module.sizing.redis.redis_maxmemory
}

module "kafka" {
  source         = "../../../modules/apps/kafka"
  root_domain    = local.domain
  namespace      = module.namespaces.infra_ns
  environment    = local.env
  oidc_enabled   = false
  enable_gateway = true
  cpu_request    = module.sizing.kafka.cpu_request
  cpu_limit      = module.sizing.kafka.cpu_limit
  memory_request = module.sizing.kafka.memory_request
  memory_limit   = module.sizing.kafka.memory_limit
  storage        = module.sizing.kafka.storage
}

module "influxdb" {
  source          = "../../../modules/apps/influxdb"
  root_domain     = local.domain
  namespace       = module.namespaces.infra_ns
  environment     = local.env
  influx_password = random_password.influx.result
  influx_token    = random_password.influx.result
  oidc_enabled    = false
  enable_gateway  = true
  cpu_request     = module.sizing.influxdb.cpu_request
  cpu_limit       = module.sizing.influxdb.cpu_limit
  memory_request  = module.sizing.influxdb.memory_request
  memory_limit    = module.sizing.influxdb.memory_limit
  storage         = module.sizing.influxdb.storage
}

module "minio" {
  source              = "../../../modules/apps/minio"
  root_domain         = local.domain
  namespace           = module.namespaces.infra_ns
  environment         = local.env
  minio_root_user     = "amminio"
  minio_root_password = random_password.minio.result
  image               = "am-local/minio:RELEASE.2025-09-07T16-13-09Z"
  oidc_enabled        = false
  enable_gateway      = true
  cpu_request         = module.sizing.minio.cpu_request
  cpu_limit           = module.sizing.minio.cpu_limit
  memory_request      = module.sizing.minio.memory_request
  memory_limit        = module.sizing.minio.memory_limit
  storage             = module.sizing.minio.storage
}

module "vault" {
  source              = "../../../modules/apps/vault"
  root_domain         = local.domain
  namespace           = module.namespaces.vault_ns
  environment         = local.env
  kubeconfig_path     = local.kubeconfig
  injector_enabled    = false
  csi_enabled         = false
  service_type        = "NodePort"
  ui_service_type     = "ClusterIP"
  enable_unsealer     = false
  enable_watcher      = true
  enable_host_aliases = false
  enable_gateway      = true
  also_match_bare     = true
  cpu_request         = module.sizing.vault.cpu_request
  cpu_limit           = module.sizing.vault.cpu_limit
  memory_request      = module.sizing.vault.memory_request
  memory_limit        = module.sizing.vault.memory_limit
}

module "db_users" {
  source = "../../../modules/core/db-users"

  namespace             = module.namespaces.infra_ns
  shared_database       = "platform"
  provision_via         = "job"
  enable_vault_secrets  = false
  enable_authentik      = false
  infra_admins_group_id = ""
  mongodb_project_id    = ""
  db_host               = "postgres-dr.asrax.in"
  mongo_host            = "mongodb-dr.asrax.in"
  postgres_admin_secret = "postgresql-secret"
  mongo_root_user       = "admin"
  mongo_root_password   = random_password.mongo.result
  redis_admin_password  = random_password.redis.result
  minio_admin_secret    = "minio-secret"

  postgresql_app_users = {
    keycloak              = { password = random_password.app_users["keycloak"].result, schemas = ["keycloak"] }
    # Temporal Helm needs dedicated DBs (not schemas on platform) for schema versioning.
    temporal              = { password = random_password.app_users["temporal"].result, database = "temporal", createdb = true, extra_databases = ["temporal_visibility"] }
    lago                  = { password = random_password.app_users["lago"].result, schemas = ["lago"], database = "lago", createdb = true }
    n8n                   = { password = random_password.app_users["n8n"].result, schemas = ["n8n"] }
    openproject           = { password = random_password.app_users["openproject"].result, schemas = ["openproject"] }
    litellm               = { password = random_password.app_users["litellm"].result, schemas = ["litellm"] }
    langfuse              = { password = random_password.app_users["langfuse"].result, schemas = ["langfuse"] }
    am_subscription_user  = { password = random_password.postgres.result, database = "am_subscription", createdb = true }
    am_user_platform_user = { password = random_password.postgres.result, database = "user_platform", createdb = true }
  }

  mongodb_app_users = {
    growthbook = { password = random_password.app_users["growthbook"].result, database = "platform", role = "readWrite" }
  }

  redis_users = {
    langfuse = { password = random_password.app_users["langfuse"].result }
  }

  minio_users = {
    langfuse = { password = random_password.app_users["langfuse"].result, prefix = "langfuse/" }
  }

  depends_on = [
    module.postgresql,
    module.mongodb,
    module.redis,
    module.minio
  ]
}

resource "null_resource" "vault_init_kv" {
  depends_on = [module.vault]

  triggers = {
    script_sha = filesha256("${path.module}/vault-init.sh")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "sed -i 's/\\r$//' '${path.module}/vault-init.sh' && bash '${path.module}/vault-init.sh'"
    environment = {
      KUBECONFIG = local.kubeconfig
    }
  }
}
