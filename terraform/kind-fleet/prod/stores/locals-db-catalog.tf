# Catalog → db-users maps (IAM access plane). Passwords in TF state until IAM-V.

locals {
  db_catalog_path = "${path.module}/../../../modules/core/db-users/catalog/users.yaml"
  db_catalog      = yamldecode(file(local.db_catalog_path))

  catalog_user_names = toset(distinct(concat(
    [for u in local.db_catalog.postgresql : u.name],
    [for u in local.db_catalog.mongodb : u.name],
    [for u in local.db_catalog.redis : u.name],
    [for u in local.db_catalog.kafka : u.name],
    [for u in local.db_catalog.minio : u.name],
  )))

  catalog_postgresql_users = {
    for u in local.db_catalog.postgresql : u.name => {
      password        = random_password.app_users[u.name].result
      database        = try(u.database, null) != null ? u.database : ""
      schemas         = try(u.schemas, null) != null ? u.schemas : []
      createdb        = try(u.createdb, false)
      extra_databases = try(u.extra_databases, null) != null ? u.extra_databases : []
    }
  }

  catalog_mongodb_users = {
    for u in local.db_catalog.mongodb : u.name => {
      password = random_password.app_users[u.name].result
      database = u.database
      role     = try(u.role, "readWrite")
    }
  }

  catalog_redis_users = {
    for u in local.db_catalog.redis : u.name => {
      password   = random_password.app_users[u.name].result
      key_prefix = try(u.key_prefix, "")
    }
  }

  catalog_kafka_users = {
    for u in local.db_catalog.kafka : u.name => {
      password     = random_password.app_users[u.name].result
      topic_prefix = try(u.topic_prefix, "")
    }
  }

  catalog_minio_users = {
    for u in local.db_catalog.minio : u.name => {
      password = random_password.app_users[u.name].result
      prefix   = try(u.prefix, "")
    }
  }
}
