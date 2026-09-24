# Thin fleet wrapper. Calls existing store modules. Does not Helm-install platform apps.

resource "terraform_data" "env_folder_guard" {
  input = local.env
  lifecycle {
    precondition {
      condition     = local.env == "dev"
      error_message = "kind-fleet/dev/stores must set local.env = \"dev\". Do not apply prod/dr sizes on the laptop."
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
  source             = "../../../modules/core/namespaces"
  environment        = local.env
  create_identity    = false
  create_apps        = false
  create_github      = false
  create_monitoring  = false
  extra_namespaces   = []
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
  # Bound Kind `standard` PVC cannot expand (allowVolumeExpansion=false). First-create uses 5Gi.
  storage         = "2Gi"
}

module "minio" {
  source              = "../../../modules/apps/minio"
  root_domain         = local.domain
  namespace           = module.namespaces.infra_ns
  environment         = local.env
  minio_root_user     = "amminio"
  minio_root_password = random_password.minio.result
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
  cpu_request         = module.sizing.vault.cpu_request
  cpu_limit           = module.sizing.vault.cpu_limit
  memory_request      = module.sizing.vault.memory_request
  memory_limit        = module.sizing.vault.memory_limit
}

module "db_users" {
  source = "../../../modules/core/db-users"

  namespace              = module.namespaces.infra_ns
  shared_database        = "platform"
  provision_via          = "job"
  enable_vault_secrets   = false
  enable_authentik       = false
  infra_admins_group_id  = ""
  mongodb_project_id     = ""
  db_host                = "postgres-dev.asrax.in"
  mongo_host             = "mongo-dev.asrax.in"
  postgres_admin_secret  = "postgresql-secret"
  mongo_root_user        = "admin"
  mongo_root_password    = random_password.mongo.result
  redis_admin_password   = random_password.redis.result
  minio_admin_secret     = "minio-secret"

  postgresql_app_users = {
    keycloak             = { password = random_password.app_users["keycloak"].result, schemas = ["keycloak"] }
    temporal             = { password = random_password.app_users["temporal"].result, schemas = ["temporal", "temporal_visibility"] }
    lago                 = { password = random_password.app_users["lago"].result, schemas = ["lago"], database = "lago", createdb = true }
    n8n                  = { password = random_password.app_users["n8n"].result, schemas = ["n8n"] }
    openproject          = { password = random_password.app_users["openproject"].result, schemas = ["openproject"] }
    litellm              = { password = random_password.app_users["litellm"].result, schemas = ["litellm"] }
    langfuse             = { password = random_password.app_users["langfuse"].result, schemas = ["langfuse"] }
    # Match apps-vault-seed AM_SUBSCRIPTION_DB_* (password = postgres admin for fleet seed)
    am_subscription_user   = { password = random_password.postgres.result, database = "am_subscription", createdb = true }
    am_user_platform_user  = { password = random_password.postgres.result, database = "user_platform", createdb = true }
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

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    command     = <<-PS
      $kube = "$env:USERPROFILE\.asrax\kubeconfig.am-dev-infra.yaml"
      $keys = "$env:USERPROFILE\.asrax\vault-dev-infra.json"
      $deadline = (Get-Date).AddMinutes(8)
      do {
        $pod = kubectl --kubeconfig $kube -n vault get pod -l app.kubernetes.io/name=vault -o jsonpath="{.items[0].metadata.name}" 2>$null
        $ready = kubectl --kubeconfig $kube -n vault get pod $pod -o jsonpath="{.status.phase}" 2>$null
        if ($ready -eq "Running") { break }
        Start-Sleep 5
      } while ((Get-Date) -lt $deadline)
      if (-not $pod) { throw "vault pod not found" }

      $status = kubectl --kubeconfig $kube -n vault exec $pod -- vault status -format=json 2>$null
      $init = $false
      if ($LASTEXITCODE -ne 0 -or -not $status) { $init = $true }
      else {
        $st = $status | ConvertFrom-Json
        if ($st.initialized -eq $false) { $init = $true }
      }
      if ($init -and -not (Test-Path $keys)) {
        $out = kubectl --kubeconfig $kube -n vault exec $pod -- vault operator init -key-shares=1 -key-threshold=1 -format=json
        Set-Content -Path $keys -Value $out -Encoding utf8
      }
      if (Test-Path $keys) {
        $j = Get-Content $keys -Raw | ConvertFrom-Json
        kubectl --kubeconfig $kube -n vault exec $pod -- vault operator unseal $j.unseal_keys_b64[0] | Out-Null
        kubectl --kubeconfig $kube -n vault exec $pod -- /bin/sh -c "VAULT_TOKEN=$($j.root_token) vault secrets enable -path=apps kv-v2" ; if ($LASTEXITCODE -ne 0) { Write-Output "apps mount may already exist" }
        $policy = @'
path "apps/data/dev/*" { capabilities = ["create","read","update","list"] }
path "apps/metadata/dev/*" { capabilities = ["list"] }
path "secret/data/dev/*" { capabilities = ["read","list"] }
path "secret/metadata/dev/*" { capabilities = ["list"] }
'@
        $tmp = [System.IO.Path]::GetTempFileName()
        Set-Content $tmp $policy
        kubectl --kubeconfig $kube -n vault cp $tmp "$($pod):/tmp/am-apps-read.hcl"
        kubectl --kubeconfig $kube -n vault exec $pod -- /bin/sh -c "VAULT_TOKEN=$($j.root_token) vault policy write am-apps-read /tmp/am-apps-read.hcl"
        Remove-Item $tmp -Force
      }
    PS
  }
}
