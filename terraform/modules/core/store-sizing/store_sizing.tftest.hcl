run "dev_minio_limit" {
  command = plan
  variables {
    environment = "dev"
  }
  assert {
    condition     = output.minio.memory_limit == "512Mi" && output.minio.cpu_limit == "500m" && output.minio.cpu_request == "50m"
    error_message = "dev MinIO must be 50m/256Mi → 500m/512Mi"
  }
}

run "dev_pg_mem" {
  command = plan
  variables {
    environment = "dev"
  }
  assert {
    condition     = output.postgresql.memory_request == "256Mi" && output.postgresql.memory_limit == "1Gi"
    error_message = "dev Postgres must request 256Mi and limit 1Gi"
  }
}

run "prod_pg_limit_is_2gi" {
  command = plan
  variables {
    environment = "prod"
  }
  assert {
    condition     = output.postgresql.memory_limit == "2Gi" && output.postgresql.storage == "16Gi"
    error_message = "prod PG limit is 2Gi and disk 16Gi (not 4Gi/32Gi)"
  }
}

run "dr_limits_match_prod_pg" {
  command = plan
  variables {
    environment = "dr"
  }
  assert {
    condition     = output.postgresql.cpu_limit == "1000m" && output.postgresql.memory_limit == "2Gi" && output.postgresql.cpu_request == "175m"
    error_message = "DR PG limits must match prod; request must be lower"
  }
}

run "prod_all_limits" {
  command = plan
  variables {
    environment = "prod"
  }
  assert {
    condition = (
      output.postgresql.cpu_limit == "1000m" && output.postgresql.memory_limit == "2Gi" &&
      output.mongodb.cpu_limit == "1000m" && output.mongodb.memory_limit == "2Gi" &&
      output.redis.cpu_limit == "400m" && output.redis.memory_limit == "1Gi" && output.redis.redis_maxmemory == "768mb" &&
      output.kafka.cpu_limit == "1000m" && output.kafka.memory_limit == "2Gi" &&
      output.influxdb.cpu_limit == "500m" && output.influxdb.memory_limit == "2Gi" &&
      output.minio.cpu_limit == "1000m" && output.minio.memory_limit == "2Gi" &&
      output.vault.cpu_limit == "500m" && output.vault.memory_limit == "512Mi"
    )
    error_message = "prod limits must match the locked PLAN table"
  }
}

run "dr_limits_equal_prod_all_stores" {
  command = plan
  variables {
    environment = "dr"
  }
  assert {
    condition = (
      output.postgresql.cpu_limit == "1000m" && output.postgresql.memory_limit == "2Gi" &&
      output.mongodb.cpu_limit == "1000m" && output.mongodb.memory_limit == "2Gi" &&
      output.redis.cpu_limit == "400m" && output.redis.memory_limit == "1Gi" &&
      output.kafka.cpu_limit == "1000m" && output.kafka.memory_limit == "2Gi" &&
      output.influxdb.cpu_limit == "500m" && output.influxdb.memory_limit == "2Gi" &&
      output.minio.cpu_limit == "1000m" && output.minio.memory_limit == "2Gi" &&
      output.vault.cpu_limit == "500m" && output.vault.memory_limit == "512Mi" &&
      output.postgresql.cpu_request == "175m" && output.mongodb.cpu_request == "175m" &&
      output.kafka.cpu_request == "140m" && output.minio.cpu_request == "140m"
    )
    error_message = "DR limits must equal prod for every store; DR requests must be lower except Redis"
  }
}
