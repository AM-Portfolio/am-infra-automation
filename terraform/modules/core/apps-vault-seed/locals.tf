locals {
  # Host naming: prod uses bare Phase-2/3 names; others use -<env> suffix.
  # Auth = Keycloak public host (auth*.asrax.in). Quarkus KC has no /auth context path.
  # Contabo dig (env=dev + store_hosts=contabo_prod): Vault paths stay apps/data/dev/*,
  # but PG/Mongo/Redis/Kafka/Influx hit Contabo prod stores — isolation = shared dig_vault_seed
  # + per-service *_dev resource names (never prod DB/prefix/topic/bucket).
  host_suffix = var.env == "prod" ? "" : "-${var.env}"
  use_contabo_prod_stores = var.store_hosts == "contabo_prod"
  # Contabo env=dev shared-cred isolation (IAM store isolation plan).
  dig_shared = local.use_contabo_prod_stores && var.env == "dev"

  pg_host = local.use_contabo_prod_stores ? "postgres.${var.domain}" : "postgres${local.host_suffix}.${var.domain}"
  mongo_host = (
    local.use_contabo_prod_stores ? "mongo.${var.domain}" :
    (var.env == "prod" ? "mongo.${var.domain}" : "mongodb-${var.env}.${var.domain}")
  )
  redis_host = local.use_contabo_prod_stores ? "redis.${var.domain}" : "redis${local.host_suffix}.${var.domain}"
  # Dev and preprod keep their own brokers even when other stores use Contabo prod hosts.
  kafka_host = (
    var.env == "dev" ? "kafka-dev.${var.domain}:9094" :
    var.env == "preprod" ? "kafka-preprod.${var.domain}:9095" :
    var.env == "prod" ? "kafka.${var.domain}:9092" :
    "kafka${local.host_suffix}.${var.domain}:9092"
  )
  influx_host = (
    local.use_contabo_prod_stores ? "influxdb.${var.domain}" :
    (var.env == "prod" ? "influx.${var.domain}" : "influxdb-${var.env}.${var.domain}")
  )
  # dig/preprod: Contabo prod Keycloak (set keycloak_public_host=auth.asrax.in).
  # DR keeps its own auth-dr Keycloak. Prod uses bare auth.asrax.in.
  auth_host = coalesce(
    var.keycloak_public_host != "" ? var.keycloak_public_host : null,
    var.env == "prod" ? "auth.${var.domain}" : "auth-${var.env}.${var.domain}"
  )
  kc_host = "https://${local.auth_host}"
  ui_base = coalesce(
    var.ui_base_url != "" ? var.ui_base_url : null,
    var.env == "prod" ? "https://am.${var.domain}" : "https://am-${var.env}.${var.domain}"
  )
  otel_host = "https://otel${local.host_suffix}.${var.domain}"

  # Per-DB app users for classic Kind dig / prod. Contabo dig uses shared dig_vault_seed only.
  db_user_suffix = var.env == "prod" ? "" : "_${var.env}"
  pg_user_platform     = local.dig_shared ? var.postgres_user : "am_user_platform_user${local.db_user_suffix}"
  pg_user_subscription = local.dig_shared ? var.postgres_user : "am_subscription_user${local.db_user_suffix}"
  mongo_user_oms       = local.dig_shared ? var.mongo_user : "am_oms_user${local.db_user_suffix}"
  mongo_user_notification = local.dig_shared ? var.mongo_user : "am_notification_user${local.db_user_suffix}"
  pg_pass_platform = local.dig_shared ? var.postgres_password : substr(sha256("pg|user_platform|${var.env}|${var.postgres_password}"), 0, 32)
  pg_pass_subscription = local.dig_shared ? var.postgres_password : substr(sha256("pg|am_subscription|${var.env}|${var.postgres_password}"), 0, 32)
  mongo_pass_oms = local.dig_shared ? var.mongo_password : substr(sha256("mongo|am_oms|${var.env}|${var.mongo_password}"), 0, 32)
  mongo_pass_notification = local.dig_shared ? var.mongo_password : substr(sha256("mongo|am_notification|${var.env}|${var.mongo_password}"), 0, 32)

  # Env=dev Contabo resource names (plan inventory). Prod / classic Kind keep legacy names.
  mongo_db = {
    oms           = local.dig_shared ? "am_oms_dev" : (var.env == "prod" ? "am_oms" : "am_oms_${var.env}")
    notification  = local.dig_shared ? "am_notification_dev" : (var.env == "prod" ? "am_notification" : "am_notification_${var.env}")
    news          = local.dig_shared ? "am_news_dev" : (var.env == "prod" ? "am_news" : "am_news_${var.env}")
    portfolio     = local.dig_shared ? "am_portfolio_dev" : (var.env == "prod" ? "portfolio" : "portfolio_${var.env}")
    trade         = local.dig_shared ? "am_trade_dev" : (var.env == "prod" ? "trade" : "trade_${var.env}")
    analysis      = local.dig_shared ? "am_analysis_dev" : (var.env == "prod" ? "analysis" : "analysis_${var.env}")
    mcp           = local.dig_shared ? "am_mcp_dev" : (var.env == "prod" ? "mcp" : "mcp_${var.env}")
    doc_intel     = local.dig_shared ? "am_doc_intel_dev" : (var.env == "prod" ? "am_docs" : "am_docs_${var.env}")
    logging       = local.dig_shared ? "am_logging_dev" : (var.env == "prod" ? "am_analytics" : "am_analytics_${var.env}")
    asrax_corp    = local.dig_shared ? "am_asrax_corp_dev" : (var.env == "prod" ? "am_asrax_corp" : "am_asrax_corp_${var.env}")
    mkt_agent     = local.dig_shared ? "am_mkt_agent_dev" : (var.env == "prod" ? "am_mkt" : "am_mkt_${var.env}")
    engage        = local.dig_shared ? "am_engage_dev" : (var.env == "prod" ? "am_engage" : "am_engage_${var.env}")
    fin_agent     = local.dig_shared ? "am_fin_agent_dev" : (var.env == "prod" ? "fin_agent" : "fin_agent_${var.env}")
    market_data   = local.dig_shared ? "market_data_dev" : (var.env == "prod" ? "market_data" : "market_data_${var.env}")
    mutual_funds  = local.dig_shared ? "mutual_funds_dev" : (var.env == "prod" ? "mutual_funds" : "mutual_funds_${var.env}")
    ui_testing    = local.dig_shared ? "am_ui_testing_dev" : (var.env == "prod" ? "am_ui_testing" : "am_ui_testing_${var.env}")
    db_agent      = local.dig_shared ? "am_db_agent_dev" : (var.env == "prod" ? "am_db_agent" : "am_db_agent_${var.env}")
    tool_agent    = local.dig_shared ? "am_tool_agent_dev" : (var.env == "prod" ? "am_tool_agent" : "am_tool_agent_${var.env}")
    qa_agent      = local.dig_shared ? "am_qa_agent_dev" : (var.env == "prod" ? "am_qa_agent" : "am_qa_agent_${var.env}")
    support_agent = local.dig_shared ? "am_support_agent_dev" : (var.env == "prod" ? "am_support_agent" : "am_support_agent_${var.env}")
  }

  pg_db_platform     = local.dig_shared ? "user_platform_dev" : (var.env == "prod" ? "user_platform" : "user_platform_${var.env}")
  pg_db_subscription = local.dig_shared ? "am_subscription_dev" : (var.env == "prod" ? "am_subscription" : "am_subscription_${var.env}")
  # QA on Contabo dig: shared dig role against user_platform_dev (restricted to *_dev DBs).
  qa_pg_db = local.dig_shared ? local.pg_db_platform : var.postgres_db

  redis_prefix = {
    market_data  = local.dig_shared ? "am-market-data-dev:" : "am-market-data:"
    gateway      = local.dig_shared ? "am-gateway-dev:" : "am-gateway:"
    portfolio    = local.dig_shared ? "am-portfolio-dev:" : "am-portfolio:"
    trade        = local.dig_shared ? "am-trade-dev:" : "am-trade:"
    analysis     = local.dig_shared ? "am-analysis-dev:" : "am-analysis:"
    oms          = local.dig_shared ? "am-oms-dev:" : "am-oms:"
    notification = local.dig_shared ? "am-notification-dev:" : "am-notification:"
    api_gateway  = local.dig_shared ? "am-api-gateway-dev:" : "am-api-gateway:"
  }

  kafka_topic_prefix = {
    market       = local.dig_shared ? "am.market.dev." : "am.market."
    gateway      = local.dig_shared ? "am.gateway.dev." : "am.gateway."
    oms          = local.dig_shared ? "am.oms.dev." : "am.oms."
    notification = local.dig_shared ? "am.notification.dev." : "am.notification."
    portfolio    = local.dig_shared ? "am.portfolio.dev." : "am.portfolio."
    trade        = local.dig_shared ? "am.trade.dev." : "am.trade."
    doc          = local.dig_shared ? "am.doc.dev." : "am.doc."
    mcp          = local.dig_shared ? "am.mcp.dev." : "am.mcp."
    logging      = local.dig_shared ? "am.logging.dev." : "am.logging."
  }

  influx_bucket_resolved = local.dig_shared ? "am_dev" : var.influx_bucket

  mongo_uri_base = "mongodb://${urlencode(var.mongo_user)}:${urlencode(var.mongo_password)}@${local.mongo_host}:27017"
  mongo_uri_auth = "${local.mongo_uri_base}/?authSource=admin&directConnection=true"
  mongo_uri_for = {
    for k, db in local.mongo_db : k => "${local.mongo_uri_base}/${db}?authSource=admin&directConnection=true"
  }

  # Shared Contabo dig principal name (same login as mongo/pg: dig_vault_seed).
  redis_username = local.dig_shared ? var.mongo_user : ""
  redis_url = local.dig_shared ? (
    "redis://${urlencode(local.redis_username)}:${urlencode(var.redis_password)}@${local.redis_host}:6379/0"
  ) : "redis://:${urlencode(var.redis_password)}@${local.redis_host}:6379/0"

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
  qa_pg_url = "postgresql+psycopg://${var.postgres_user}:${var.postgres_password}@${local.pg_host}:5432/${local.qa_pg_db}"

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
      svc == "am-asrax-corp" ? {
        MONGO_URI = local.mongo_uri_for.asrax_corp
        MONGO_DB  = local.mongo_db.asrax_corp
        MINIO_ENDPOINT = ""
      } : {},
      svc == "am-mkt-agents" ? {
        MONGO_URI = local.mongo_uri_for.mkt_agent
        MONGO_DB  = local.mongo_db.mkt_agent
      } : {},
      # IAM: catalog hardcodes prod DB names/users; overlay env-suffixed / shared dig principals last.
      svc == "am-user-platform" ? {
        AM_USER_PLATFORM_DB_NAME     = local.infra_postgres.AM_USER_PLATFORM_DB_NAME
        AM_USER_PLATFORM_DB_USER     = local.infra_postgres.AM_USER_PLATFORM_DB_USER
        AM_USER_PLATFORM_DB_PASSWORD = local.infra_postgres.AM_USER_PLATFORM_DB_PASSWORD
      } : {},
      svc == "am-subscription" ? {
        AM_SUBSCRIPTION_DB_NAME     = local.infra_postgres.AM_SUBSCRIPTION_DB_NAME
        AM_SUBSCRIPTION_DB_USER     = local.infra_postgres.AM_SUBSCRIPTION_DB_USER
        AM_SUBSCRIPTION_DB_PASSWORD = local.infra_postgres.AM_SUBSCRIPTION_DB_PASSWORD
      } : {},
      svc == "am-oms" ? {
        AM_OMS_MONGO_URI      = local.mongo_uri_for.oms
        AM_OMS_MONGO_DATABASE = local.mongo_db.oms
        AM_OMS_DB_USER        = local.mongo_user_oms
        AM_OMS_DB_PASSWORD    = local.mongo_pass_oms
        KAFKA_TOPIC_PREFIX    = local.kafka_topic_prefix.oms
      } : {},
      svc == "am-notification" ? {
        AM_NOTIFICATION_MONGO_URI      = local.mongo_uri_for.notification
        AM_NOTIFICATION_MONGO_DATABASE = local.mongo_db.notification
        AM_NOTIFICATION_DB_USER        = local.mongo_user_notification
        AM_NOTIFICATION_DB_PASSWORD    = local.mongo_pass_notification
        KAFKA_TOPIC_PREFIX             = local.kafka_topic_prefix.notification
      } : {},
      svc == "am-news" ? {
        MONGO_DB               = local.mongo_db.news
        MONGO_URI              = local.mongo_uri_for.news
        MONGODB_DATABASE       = local.mongo_db.news
        SPRING_DATA_MONGODB_DATABASE = local.mongo_db.news
      } : {},
      svc == "am-portfolio" ? {
        MONGODB_DATABASE             = local.mongo_db.portfolio
        SPRING_DATA_MONGODB_DATABASE = local.mongo_db.portfolio
        MONGODB_DATABASE_NAME        = local.mongo_db.portfolio
        REDIS_KEY_PREFIX             = local.redis_prefix.portfolio
        KAFKA_TOPIC_PREFIX           = local.kafka_topic_prefix.portfolio
      } : {},
      svc == "am-trade-management" ? {
        MONGODB_DATABASE             = local.mongo_db.trade
        SPRING_DATA_MONGODB_DATABASE = local.mongo_db.trade
        REDIS_KEY_PREFIX             = local.redis_prefix.trade
        KAFKA_TOPIC_PREFIX           = local.kafka_topic_prefix.trade
      } : {},
      svc == "am-analysis" ? {
        MONGODB_DATABASE             = local.mongo_db.analysis
        SPRING_DATA_MONGODB_DATABASE = local.mongo_db.analysis
        REDIS_KEY_PREFIX             = local.redis_prefix.analysis
      } : {},
      svc == "am-mcp-server" ? {
        MONGODB_DATABASE             = local.mongo_db.mcp
        SPRING_DATA_MONGODB_DATABASE = local.mongo_db.mcp
        KAFKA_TOPIC_PREFIX           = local.kafka_topic_prefix.mcp
      } : {},
      svc == "am-document-processor" ? {
        MONGODB_DATABASE             = local.mongo_db.doc_intel
        SPRING_DATA_MONGODB_DATABASE = local.mongo_db.doc_intel
        KAFKA_TOPIC_PREFIX           = local.kafka_topic_prefix.doc
      } : {},
      svc == "am-email-extractor" ? {
        MONGODB_DATABASE             = local.mongo_db.doc_intel
        SPRING_DATA_MONGODB_DATABASE = local.mongo_db.doc_intel
        KAFKA_TOPIC_PREFIX           = local.kafka_topic_prefix.doc
      } : {},
      svc == "am-logging" || svc == "logging" ? {
        MONGO_DB         = local.mongo_db.logging
        MONGODB_DATABASE = local.mongo_db.logging
        MONGO_URL        = local.mongo_uri_for.logging
      } : {},
      svc == "am-fin-agent" ? {
        MONGO_DB         = local.mongo_db.fin_agent
        DB_NAME          = local.mongo_db.fin_agent
        MONGODB_DATABASE = local.mongo_db.fin_agent
        MONGODB_URI      = local.mongo_uri_for.fin_agent
      } : {},
      svc == "am-market-data" ? {
        MONGODB_DATABASE             = local.mongo_db.market_data
        MONGODB_DATABASE_NAME        = local.mongo_db.market_data
        SPRING_DATA_MONGODB_DATABASE = local.mongo_db.market_data
        REDIS_KEY_PREFIX             = local.redis_prefix.market_data
        KAFKA_TOPIC_PREFIX           = local.kafka_topic_prefix.market
        INFLUXDB_BUCKET              = local.influx_bucket_resolved
        SPRING_INFLUX_BUCKET         = local.influx_bucket_resolved
      } : {},
      svc == "am-parser" ? {
        MONGODB_DATABASE             = local.mongo_db.mutual_funds
        SPRING_DATA_MONGODB_DATABASE = local.mongo_db.mutual_funds
      } : {},
      svc == "am-engage" ? {
        MONGO_URI = local.mongo_uri_for.engage
        MONGO_DB  = local.mongo_db.engage
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
    host                         = local.pg_host
    port                         = "5432"
    database                     = local.dig_shared ? local.pg_db_platform : var.postgres_db
    username                     = var.postgres_user
    password                     = var.postgres_password
    url                          = "jdbc:postgresql://${local.pg_host}:5432/${local.dig_shared ? local.pg_db_platform : var.postgres_db}"
    DATABASE_URL                 = "postgresql://${var.postgres_user}:${var.postgres_password}@${local.pg_host}:5432/${local.dig_shared ? local.pg_db_platform : var.postgres_db}"
    POSTGRES_HOST                = local.pg_host
    POSTGRES_PORT                = "5432"
    POSTGRES_USER                = var.postgres_user
    POSTGRES_PASSWORD            = var.postgres_password
    AM_USER_PLATFORM_DB_NAME     = local.pg_db_platform
    AM_USER_PLATFORM_DB_USER     = local.pg_user_platform
    AM_USER_PLATFORM_DB_PASSWORD = local.pg_pass_platform
    AM_SUBSCRIPTION_DB_NAME      = local.pg_db_subscription
    AM_SUBSCRIPTION_DB_USER      = local.pg_user_subscription
    AM_SUBSCRIPTION_DB_PASSWORD  = local.pg_pass_subscription
  }

  infra_mongodb = merge(
    {
      host                         = local.mongo_host
      port                         = "27017"
      username                     = var.mongo_user
      password                     = var.mongo_password
      authSource                   = "admin"
      url                          = local.mongo_uri_auth
      database                     = local.mongo_db.portfolio
      AM_OMS_MONGO_DATABASE        = local.mongo_db.oms
      AM_OMS_MONGO_URI             = local.mongo_uri_for.oms
      AM_OMS_DB_USER               = local.mongo_user_oms
      AM_OMS_DB_PASSWORD           = local.mongo_pass_oms
      AM_NOTIFICATION_MONGO_DATABASE = local.mongo_db.notification
      AM_NOTIFICATION_MONGO_URI    = local.mongo_uri_for.notification
      AM_NOTIFICATION_DB_USER      = local.mongo_user_notification
      AM_NOTIFICATION_DB_PASSWORD  = local.mongo_pass_notification
      AM_PORTFOLIO_MONGO_DATABASE  = local.mongo_db.portfolio
      AM_TRADE_MONGO_DATABASE      = local.mongo_db.trade
      AM_ANALYSIS_MONGO_DATABASE   = local.mongo_db.analysis
      AM_NEWS_MONGO_DATABASE       = local.mongo_db.news
      AM_MCP_MONGO_DATABASE        = local.mongo_db.mcp
      AM_DOC_INTEL_MONGO_DATABASE  = local.mongo_db.doc_intel
      AM_LOGGING_MONGO_DATABASE    = local.mongo_db.logging
      AM_ASRAX_CORP_MONGO_DATABASE = local.mongo_db.asrax_corp
      AM_MKT_AGENT_MONGO_DATABASE  = local.mongo_db.mkt_agent
      AM_ENGAGE_MONGO_DATABASE     = local.mongo_db.engage
      AM_FIN_AGENT_MONGO_DATABASE  = local.mongo_db.fin_agent
      AM_MARKET_DATA_MONGO_DATABASE = local.mongo_db.market_data
      AM_PARSER_MONGO_DATABASE     = local.mongo_db.mutual_funds
      AM_UI_TESTING_MONGO_DATABASE = local.mongo_db.ui_testing
      MONGODB_DATABASE             = local.mongo_db.portfolio
      SPRING_DATA_MONGODB_DATABASE = local.mongo_db.portfolio
    }
  )

  infra_redis = merge(
    {
      host     = local.redis_host
      port     = "6379"
      password = var.redis_password
      db       = "0"
      url      = local.redis_url
    },
    local.dig_shared ? {
      username       = local.redis_username
      REDIS_USERNAME = local.redis_username
      REDIS_PASSWORD = var.redis_password
      key_prefix     = local.redis_prefix.market_data
    } : {}
  )

  # Dedicated broker per env. Catalog topic names have no prefix.
  # Empty username on PLAINTEXT so apps do not attempt SASL.
  schema_registry_url = (
    var.env == "dev" ? "https://schema-registry-dev.${var.domain}" :
    var.env == "preprod" ? "https://schema-registry-preprod.${var.domain}" :
    "https://schema-registry.${var.domain}"
  )
  infra_kafka = {
    bootstrap_servers       = local.kafka_host
    username                = ""
    password                = ""
    sasl_mechanism          = "PLAIN"
    security_protocol       = "PLAINTEXT"
    KAFKA_SASL_MECHANISM    = "PLAIN"
    KAFKA_SECURITY_PROTOCOL = "PLAINTEXT"
    schema_registry_url     = local.schema_registry_url
  }

  infra_influxdb = {
    host            = local.influx_host
    port            = "443"
    org             = var.influx_org
    bucket          = local.influx_bucket_resolved
    token           = var.influx_token
    password        = var.influx_password
    url             = "https://${local.influx_host}"
    INFLUXDB_URL    = "https://${local.influx_host}"
    INFLUXDB_ORG    = var.influx_org
    INFLUXDB_BUCKET = local.influx_bucket_resolved
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
