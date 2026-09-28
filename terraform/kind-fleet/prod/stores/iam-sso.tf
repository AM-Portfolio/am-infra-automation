# iam-sso Phase 2 — MinIO Keycloak OIDC + store UI oauth2-proxy + Vault UI OIDC.
# Pass secrets at apply from Vault apps/data/prod/oidc/* (written by platform).

variable "oidc_client_secrets" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = "Map of Keycloak client_id → secret (minio, vault-ui, kafka-ui, pgadmin, …)."
}

locals {
  oidc_issuer = "https://auth.asrax.in/realms/am-realm"
  oidc_sec = {
    for k in ["minio", "vault-ui", "kafka-ui", "pgadmin", "mongo-express", "redis-ui", "influx-ui", "traefik"] :
    k => try(var.oidc_client_secrets[k], "")
  }
}

module "oauth2_kafka_ui" {
  source         = "../../../modules/apps/oauth2-proxy"
  count          = local.oidc_sec["kafka-ui"] != "" ? 1 : 0
  name           = "kafka-ui"
  namespace      = module.namespaces.infra_ns
  issuer_url     = local.oidc_issuer
  client_id      = "kafka-ui"
  client_secret  = local.oidc_sec["kafka-ui"]
  upstream       = "http://kafka-ui.${module.namespaces.infra_ns}.svc:8080"
  redirect_url   = "https://kafka-ui.${local.domain}/oauth2/callback"
  host           = "kafka-ui.${local.domain}"
  enable_gateway = true

  depends_on = [module.kafka]
}

module "oauth2_pgadmin" {
  source         = "../../../modules/apps/oauth2-proxy"
  count          = local.oidc_sec["pgadmin"] != "" ? 1 : 0
  name           = "pgadmin"
  namespace      = module.namespaces.infra_ns
  issuer_url     = local.oidc_issuer
  client_id      = "pgadmin"
  client_secret  = local.oidc_sec["pgadmin"]
  upstream       = "http://pgadmin.${module.namespaces.infra_ns}.svc:80"
  redirect_url   = "https://pgadmin.${local.domain}/oauth2/callback"
  host           = "pgadmin.${local.domain}"
  enable_gateway = true

  depends_on = [module.postgresql]
}

module "oauth2_mongo_express" {
  source         = "../../../modules/apps/oauth2-proxy"
  count          = local.oidc_sec["mongo-express"] != "" ? 1 : 0
  name           = "mongo-express"
  namespace      = module.namespaces.infra_ns
  issuer_url     = local.oidc_issuer
  client_id      = "mongo-express"
  client_secret  = local.oidc_sec["mongo-express"]
  upstream       = "http://mongo-express.${module.namespaces.infra_ns}.svc:8081"
  redirect_url   = "https://mongo-express.${local.domain}/oauth2/callback"
  host           = "mongo-express.${local.domain}"
  enable_gateway = true

  depends_on = [module.mongodb]
}

module "oauth2_redis_ui" {
  source         = "../../../modules/apps/oauth2-proxy"
  count          = local.oidc_sec["redis-ui"] != "" ? 1 : 0
  name           = "redis-ui"
  namespace      = module.namespaces.infra_ns
  issuer_url     = local.oidc_issuer
  client_id      = "redis-ui"
  client_secret  = local.oidc_sec["redis-ui"]
  upstream       = "http://redis-commander.${module.namespaces.infra_ns}.svc:8081"
  redirect_url   = "https://redis-ui.${local.domain}/oauth2/callback"
  host           = "redis-ui.${local.domain}"
  enable_gateway = true

  depends_on = [module.redis]
}
