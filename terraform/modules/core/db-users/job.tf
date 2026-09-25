# In-cluster provisioner for fleet: few shared DBs, many users/schemas.
# Used when provision_via=job so the laptop does not need a Postgres driver.

locals {
  pg_job_sh = join("\n", concat(
    [
      "set -eu",
      "for i in $(seq 1 60); do pg_isready -h postgresql && break; sleep 2; done"
    ],
    local.shared_mode ? [
      "psql -d postgres -tc \"SELECT 1 FROM pg_database WHERE datname='${var.shared_database}'\" | grep -q 1 || psql -d postgres -c 'CREATE DATABASE ${var.shared_database}'"
    ] : [
      for user, spec in var.postgresql_app_users :
      "psql -d postgres -tc \"SELECT 1 FROM pg_database WHERE datname='${spec.database != "" ? spec.database : user}'\" | grep -q 1 || psql -d postgres -c 'CREATE DATABASE ${spec.database != "" ? spec.database : user}'"
    ],
    [
      for user, spec in var.postgresql_app_users :
      "psql -d postgres -c \"DO \\$\\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='${user}') THEN CREATE ROLE ${user} LOGIN PASSWORD '${replace(spec.password, "'", "''")}'; ELSE ALTER ROLE ${user} PASSWORD '${replace(spec.password, "'", "''")}'; END IF; END \\$\\$;\""
    ],
    # Dedicated DBs even in shared_mode (Lago Rails db:create needs its own DB + CREATEDB).
    [
      for user, spec in var.postgresql_app_users :
      "psql -d postgres -tc \"SELECT 1 FROM pg_database WHERE datname='${spec.database != "" ? spec.database : user}'\" | grep -q 1 || psql -d postgres -c \"CREATE DATABASE ${spec.database != "" ? spec.database : user} OWNER ${user}\""
      if spec.database != "" || try(spec.createdb, false)
    ],
    [
      for user, spec in var.postgresql_app_users :
      "psql -d postgres -c 'ALTER ROLE ${user} WITH CREATEDB'"
      if try(spec.createdb, false)
    ],
    [
      for user, spec in var.postgresql_app_users :
      "psql -d postgres -c 'ALTER ROLE ${user} SET search_path TO public'"
      if spec.database != "" || try(spec.createdb, false)
    ],
    # Dedicated DB ownership (restored dumps often leave tables owned by postgres).
    [
      for user, spec in var.postgresql_app_users :
      "psql -d ${spec.database != "" ? spec.database : user} -c \"ALTER DATABASE ${spec.database != "" ? spec.database : user} OWNER TO ${user}; GRANT ALL ON SCHEMA public TO ${user}; REASSIGN OWNED BY postgres TO ${user}; GRANT ALL ON ALL TABLES IN SCHEMA public TO ${user}; GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO ${user}; ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${user}; ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${user}; DO \\$\\$ DECLARE r record; BEGIN FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP EXECUTE format('ALTER TABLE public.%I OWNER TO ${user}', r.tablename); END LOOP; FOR r IN SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'public' LOOP EXECUTE format('ALTER SEQUENCE public.%I OWNER TO ${user}', r.sequence_name); END LOOP; END \\$\\$;\""
      if spec.database != "" || try(spec.createdb, false)
    ],
    local.shared_mode ? flatten([
      for item in values(local.pg_schema_map) : [
        "psql -d ${var.shared_database} -c 'GRANT CONNECT ON DATABASE ${var.shared_database} TO ${item.user}'",
        "psql -d ${var.shared_database} -c 'CREATE SCHEMA IF NOT EXISTS ${item.schema} AUTHORIZATION ${item.user}'",
        "psql -d ${var.shared_database} -c 'GRANT ALL ON SCHEMA ${item.schema} TO ${item.user}'",
        # Skip search_path pin when the app owns a dedicated DB (Lago uses public on DB lago).
        (
          try(var.postgresql_app_users[item.user].database, "") != "" || try(var.postgresql_app_users[item.user].createdb, false)
          ? "true"
          : "psql -d ${var.shared_database} -c 'ALTER ROLE ${item.user} SET search_path TO ${item.schema}'"
        )
      ]
    ]) : []
  ))
}

resource "kubernetes_config_map" "provision_scripts" {
  count = local.use_job ? 1 : 0
  metadata {
    name      = "db-users-provision"
    namespace = var.namespace
  }
  data = {
    "pg.sh" = local.pg_job_sh
  }
}

resource "kubernetes_job" "postgres_users" {
  count = local.use_job && length(var.postgresql_app_users) > 0 ? 1 : 0

  metadata {
    name      = "db-users-postgres"
    namespace = var.namespace
  }

  spec {
    backoff_limit              = 8
    ttl_seconds_after_finished = 600
    template {
      metadata { labels = { app = "db-users-postgres" } }
      spec {
        restart_policy = "OnFailure"
        node_selector  = { role = "infra" }
        container {
          name  = "psql"
          image = "postgres:16-alpine"
          env {
            name = "PGPASSWORD"
            value_from {
              secret_key_ref {
                name = var.postgres_admin_secret
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          env {
            name = "PGUSER"
            value_from {
              secret_key_ref {
                name = var.postgres_admin_secret
                key  = "POSTGRES_USER"
              }
            }
          }
          env {
            name  = "PGHOST"
            value = "postgresql"
          }
          command = ["/bin/sh", "/scripts/pg.sh"]
          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
          }
        }
        volume {
          name = "scripts"
          config_map {
            name         = kubernetes_config_map.provision_scripts[0].metadata[0].name
            default_mode = "0755"
          }
        }
      }
    }
  }

  wait_for_completion = true
  timeouts { create = "8m" }
}

resource "kubernetes_job" "mongo_users" {
  count = local.use_job && length(var.mongodb_app_users) > 0 ? 1 : 0

  metadata {
    name      = "db-users-mongo"
    namespace = var.namespace
  }

  spec {
    backoff_limit              = 8
    ttl_seconds_after_finished = 600
    template {
      metadata { labels = { app = "db-users-mongo" } }
      spec {
        restart_policy = "OnFailure"
        node_selector  = { role = "infra" }
        container {
          name  = "mongosh"
          image = "mongo:7"
          env {
            name  = "MONGO_URI"
            value = "mongodb://${var.mongo_root_user}:${var.mongo_root_password}@mongodb:27017/admin"
          }
          command = ["/bin/sh", "-c"]
          args = [
            join("\n", concat(
              [
                "set -eu",
                "for i in $(seq 1 60); do mongosh --quiet \"$MONGO_URI\" --eval 'db.runCommand({ ping: 1 })' && break; sleep 2; done"
              ],
              [
                for user, spec in var.mongodb_app_users :
                "mongosh --quiet \"$MONGO_URI\" --eval 'try { db.getSiblingDB(\"${local.shared_mode && spec.database == "" ? var.shared_database : (spec.database != "" ? spec.database : user)}\").createUser({ user: \"${user}\", pwd: \"${spec.password}\", roles: [{ role: \"${spec.role != "" ? spec.role : "readWrite"}\", db: \"${local.shared_mode && spec.database == "" ? var.shared_database : (spec.database != "" ? spec.database : user)}\" }] }) } catch (e) { if (!/already exists/.test(e.message)) throw e }'"
              ]
            ))
          ]
        }
      }
    }
  }

  wait_for_completion = true
  timeouts { create = "8m" }
}

resource "kubernetes_job" "redis_users" {
  count = local.use_job && length(var.redis_users) > 0 ? 1 : 0

  metadata {
    name      = "db-users-redis"
    namespace = var.namespace
  }

  spec {
    backoff_limit              = 8
    ttl_seconds_after_finished = 600
    template {
      metadata { labels = { app = "db-users-redis" } }
      spec {
        restart_policy = "OnFailure"
        node_selector  = { role = "infra" }
        container {
          name  = "redis"
          image = "redis:7.2-alpine"
          env {
            name  = "REDISCLI_AUTH"
            value = var.redis_admin_password
          }
          command = ["/bin/sh", "-c"]
          args = [
            join("\n", concat(
              ["set -eu"],
              [for user, spec in var.redis_users : "redis-cli -h redis-master ACL SETUSER ${user} on >${spec.password} '~*' '+@all'"]
            ))
          ]
        }
      }
    }
  }

  wait_for_completion = true
  timeouts { create = "6m" }
}

resource "kubernetes_job" "minio_users" {
  count = local.use_job && length(var.minio_users) > 0 ? 1 : 0

  metadata {
    name      = "db-users-minio"
    namespace = var.namespace
  }

  spec {
    backoff_limit              = 8
    ttl_seconds_after_finished = 600
    template {
      metadata { labels = { app = "db-users-minio" } }
      spec {
        restart_policy = "OnFailure"
        node_selector  = { role = "infra" }
        container {
          name  = "mc"
          image = "am-local/mc:RELEASE.2025-08-13T08-35-41Z"
          env {
            name = "MINIO_ROOT_USER"
            value_from {
              secret_key_ref {
                name = var.minio_admin_secret
                key  = "MINIO_ROOT_USER"
              }
            }
          }
          env {
            name = "MINIO_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = var.minio_admin_secret
                key  = "MINIO_ROOT_PASSWORD"
              }
            }
          }
          command = ["/bin/sh", "-c"]
          args = [
            join("\n", concat(
              [
                "set -eu",
                "mc alias set local http://minio:9000 \"$MINIO_ROOT_USER\" \"$MINIO_ROOT_PASSWORD\"",
                "mc mb --ignore-existing local/platform"
              ],
              [for user, spec in var.minio_users : "mc admin user add local ${user} ${spec.password} || true"]
            ))
          ]
        }
      }
    }
  }

  wait_for_completion = true
  timeouts { create = "6m" }
}
