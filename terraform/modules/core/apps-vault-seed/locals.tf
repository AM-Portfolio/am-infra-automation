locals {
  # Host naming: prod uses bare Phase-2/3 names; others use -<env> suffix.
  # Auth = Keycloak public host (auth*.asrax.in). Quarkus KC has no /auth context path.
  host_suffix = var.env == "prod" ? "" : "-${var.env}"
  pg_host     = "postgres${local.host_suffix}.${var.domain}"
  mongo_host  = var.env == "prod" ? "mongo.${var.domain}" : "mongodb-${var.env}.${var.domain}"
  redis_host  = "redis${local.host_suffix}.${var.domain}"
  kafka_host  = "kafka${local.host_suffix}.${var.domain}:9092"
  influx_host = var.env == "prod" ? "influx.${var.domain}" : "influxdb-${var.env}.${var.domain}"
  auth_host   = var.env == "prod" ? "auth.${var.domain}" : "auth-${var.env}.${var.domain}"
  kc_host     = "https://${local.auth_host}"
  ui_base = coalesce(
    var.ui_base_url != "" ? var.ui_base_url : null,
    var.env == "prod" ? "https://am.${var.domain}" : "https://am-${var.env}.${var.domain}"
  )
  otel_host = "https://otel${local.host_suffix}.${var.domain}"

  catalog = yamldecode(file("${path.module}/catalog/services.yaml"))

  # Shared keys merged into every services/* path (pods that mount service secrets).
  base_service = {
    KEYCLOAK_URL         = local.kc_host
    KEYCLOAK_REALM       = var.keycloak_realm
    OIDC_ISSUER          = "${local.kc_host}/realms/${var.keycloak_realm}"
    OIDC_DISCOVERY_URL   = "${local.kc_host}/realms/${var.keycloak_realm}/.well-known/openid-configuration"
    OIDC_JWKS_URL        = "${local.kc_host}/realms/${var.keycloak_realm}/protocol/openid-connect/certs"
    OIDC_TOKEN_URL       = "${local.kc_host}/realms/${var.keycloak_realm}/protocol/openid-connect/token"
    OIDC_AUDIENCE        = "account"
    AUTH_UI_BASE_URL     = local.ui_base
    JWT_SECRET           = "${var.env}-fleet-jwt-placeholder"
    JWT_SECRET_KEY       = "${var.env}-fleet-jwt-placeholder"
    SECRET_KEY           = "${var.env}-fleet-secret-key-placeholder"
    DATABASE_URL         = "postgresql://${var.postgres_user}:${var.postgres_password}@${local.pg_host}:5432/${var.postgres_db}"
    ALLOWED_GOOGLE_REDIRECT_URIS = "${local.ui_base}/callback"
    TRACING_SAMPLING_PROBABILITY = "0.1"
  }

  # Resolve catalog values: null/empty → fleet placeholder; expand __UI_BASE__ / __ENV__.
  # KEYCLOAK_ADMIN_* skipped here — injected from var.keycloak_admin_* (never placeholders).
  catalog_resolved = {
    for svc, cfg in local.catalog.services : svc => {
      for k, v in try(cfg.keys, {}) :
      k => (
        v == null || v == "" ?
        "${var.env}-fleet-${lower(replace(k, "_", "-"))}" :
        replace(
          replace(tostring(v), "__UI_BASE__", local.ui_base),
          "__ENV__",
          var.env
        )
      )
      if !startswith(k, "KEYCLOAK_ADMIN_")
    }
  }

  kc_admin_overlay = {
    KEYCLOAK_ADMIN_USER     = var.keycloak_admin_user
    KEYCLOAK_ADMIN_PASSWORD = var.keycloak_admin_password
  }

  # Services that declare KEYCLOAK_ADMIN_* in catalog (identity always).
  services_needing_kc_admin = toset(concat(
    ["am-identity"],
    [
      for svc, cfg in local.catalog.services : svc
      if contains(keys(try(cfg.keys, {})), "KEYCLOAK_ADMIN_PASSWORD")
        || contains(keys(try(cfg.keys, {})), "KEYCLOAK_ADMIN_USER")
    ]
  ))

  # psycopg URLs for Python agents (qa-agent store)
  qa_pg_url = "postgresql+psycopg://${var.postgres_user}:${var.postgres_password}@${local.pg_host}:5432/${var.postgres_db}"

  services_data = {
    for svc, keys in local.catalog_resolved : svc => merge(
      local.base_service,
      keys,
      contains(local.services_needing_kc_admin, svc) ? local.kc_admin_overlay : {},
      try(var.extra_service_data[svc], {}),
      svc == "am-qa-agents" ? {
        QA_AGENT_DATABASE_URL = local.qa_pg_url
        SPT_DATABASE_URL      = local.qa_pg_url
      } : {},
      svc == "am-asrax-corp" || svc == "am-mkt-agents" ? {
        MONGO_URI = "mongodb://${var.mongo_user}:${var.mongo_password}@${local.mongo_host}:27017/?authSource=admin&directConnection=true"
      } : {},
      # Fleet: minio-*.asrax.in was CF-proxied; empty → corp uses local attachments (health stays up)
      svc == "am-asrax-corp" ? {
        MINIO_ENDPOINT = ""
      } : {}
    )
  }

  identity_admin_password = try(local.services_data["am-identity"]["KEYCLOAK_ADMIN_PASSWORD"], "")
  identity_admin_is_placeholder = (
    local.identity_admin_password == "" ||
    endswith(local.identity_admin_password, "-fleet-keycloak-admin-password")
  )

  # Domain path used by qa-agent Helm (apps/data/<env>/runtime/modules/qa)
  runtime_modules_data = {
    qa = merge(
      try(local.services_data["am-qa-agents"], {}),
      {
        QA_AGENT_DATABASE_URL = local.qa_pg_url
        SPT_DATABASE_URL      = local.qa_pg_url
      }
    )
  }

  infra_postgres = {
    host                       = local.pg_host
    port                       = "5432"
    database                   = var.postgres_db
    username                   = var.postgres_user
    password                   = var.postgres_password
    url                        = "jdbc:postgresql://${local.pg_host}:5432/${var.postgres_db}"
    DATABASE_URL               = "postgresql://${var.postgres_user}:${var.postgres_password}@${local.pg_host}:5432/${var.postgres_db}"
    POSTGRES_HOST              = local.pg_host
    POSTGRES_PORT              = "5432"
    POSTGRES_USER              = var.postgres_user
    POSTGRES_PASSWORD          = var.postgres_password
    AM_USER_PLATFORM_DB_NAME   = "user_platform"
    AM_USER_PLATFORM_DB_USER   = "am_user_platform_user"
    AM_USER_PLATFORM_DB_PASSWORD = var.postgres_password
    AM_SUBSCRIPTION_DB_NAME    = "am_subscription"
    AM_SUBSCRIPTION_DB_USER    = "am_subscription_user"
    AM_SUBSCRIPTION_DB_PASSWORD = var.postgres_password
  }

  infra_mongodb = {
    host                         = local.mongo_host
    port                         = "27017"
    username                     = var.mongo_user
    password                     = var.mongo_password
    authSource                   = "admin"
    url                          = "mongodb://${var.mongo_user}:${var.mongo_password}@${local.mongo_host}:27017/?authSource=admin&directConnection=true"
    AM_OMS_MONGO_DATABASE        = "am_oms"
    AM_OMS_DB_USER               = "am_oms_user"
    AM_OMS_DB_PASSWORD           = var.mongo_password
    AM_NOTIFICATION_MONGO_DATABASE = "am_notification"
    AM_NOTIFICATION_DB_USER      = "am_notification_user"
    AM_NOTIFICATION_DB_PASSWORD  = var.mongo_password
  }

  infra_redis = {
    host     = local.redis_host
    port     = "6379"
    password = var.redis_password
    db       = "0"
    url      = "redis://:${var.redis_password}@${local.redis_host}:6379/0"
  }

  infra_kafka = {
    bootstrap_servers      = local.kafka_host
    username               = ""
    password               = ""
    sasl_mechanism         = "PLAIN"
    security_protocol      = "PLAINTEXT"
    KAFKA_SASL_MECHANISM   = "PLAIN"
    KAFKA_SECURITY_PROTOCOL = "PLAINTEXT"
  }

  infra_influxdb = {
    host            = local.influx_host
    port            = "443"
    org             = var.influx_org
    bucket          = var.influx_bucket
    token           = var.influx_token
    password        = var.influx_password
    url             = "https://${local.influx_host}"
    INFLUXDB_URL    = "https://${local.influx_host}"
    INFLUXDB_ORG    = var.influx_org
    INFLUXDB_BUCKET = var.influx_bucket
    INFLUXDB_TOKEN  = var.influx_token
  }

  infra_observability = {
    MANAGEMENT_OTLP_TRACING_ENDPOINT = "${local.otel_host}:4318/v1/traces"
    MANAGEMENT_TRACING_ENABLED       = "false"
    OTEL_EXPORTER_OTLP_ENDPOINT      = "${local.otel_host}:4318"
    OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = "${local.otel_host}:4318/v1/traces"
    OTEL_SDK_DISABLED                = "true"
    TRACING_SAMPLING_PROBABILITY     = "0.1"
  }

  # Shared third-party API keys (parser mounts apps/.../infra/shared-api)
  infra_shared_api = {
    TOGETHER_API_KEY = "${var.env}-fleet-together-api-key"
    OPENAI_API_KEY   = "${var.env}-fleet-openai-api-key"
  }
}
