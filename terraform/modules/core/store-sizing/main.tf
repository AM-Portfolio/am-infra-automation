# Evidence-based store CPU/memory/disk. Module defaults elsewhere = this dev row.
# Prod disk 16Gi until asrax-db-backups is measured. DR limits = prod; requests ~70%.

locals {
  sizes = {
    dev = {
      postgresql = { cpu_request = "50m", cpu_limit = "500m", memory_request = "256Mi", memory_limit = "1Gi", storage = "5Gi", redis_maxmemory = "" }
      mongodb    = { cpu_request = "50m", cpu_limit = "500m", memory_request = "512Mi", memory_limit = "1Gi", storage = "5Gi", redis_maxmemory = "" }
      redis      = { cpu_request = "50m", cpu_limit = "200m", memory_request = "256Mi", memory_limit = "512Mi", storage = "1Gi", redis_maxmemory = "256mb" }
      kafka      = { cpu_request = "50m", cpu_limit = "500m", memory_request = "512Mi", memory_limit = "1Gi", storage = "5Gi", redis_maxmemory = "" }
      influxdb   = { cpu_request = "50m", cpu_limit = "500m", memory_request = "512Mi", memory_limit = "1Gi", storage = "5Gi", redis_maxmemory = "" }
      minio      = { cpu_request = "50m", cpu_limit = "500m", memory_request = "256Mi", memory_limit = "512Mi", storage = "5Gi", redis_maxmemory = "" }
      vault      = { cpu_request = "50m", cpu_limit = "200m", memory_request = "128Mi", memory_limit = "256Mi", storage = "", redis_maxmemory = "" }
    }
    prod = {
      postgresql = { cpu_request = "250m", cpu_limit = "1000m", memory_request = "1Gi", memory_limit = "2Gi", storage = "16Gi", redis_maxmemory = "" }
      mongodb    = { cpu_request = "250m", cpu_limit = "1000m", memory_request = "1Gi", memory_limit = "2Gi", storage = "16Gi", redis_maxmemory = "" }
      redis      = { cpu_request = "100m", cpu_limit = "400m", memory_request = "256Mi", memory_limit = "1Gi", storage = "4Gi", redis_maxmemory = "768mb" }
      kafka      = { cpu_request = "200m", cpu_limit = "1000m", memory_request = "1Gi", memory_limit = "2Gi", storage = "10Gi", redis_maxmemory = "" }
      influxdb   = { cpu_request = "100m", cpu_limit = "500m", memory_request = "1Gi", memory_limit = "2Gi", storage = "5Gi", redis_maxmemory = "" }
      minio      = { cpu_request = "200m", cpu_limit = "1000m", memory_request = "512Mi", memory_limit = "2Gi", storage = "20Gi", redis_maxmemory = "" }
      vault      = { cpu_request = "100m", cpu_limit = "500m", memory_request = "256Mi", memory_limit = "512Mi", storage = "", redis_maxmemory = "" }
    }
    dr = {
      postgresql = { cpu_request = "175m", cpu_limit = "1000m", memory_request = "768Mi", memory_limit = "2Gi", storage = "16Gi", redis_maxmemory = "" }
      mongodb    = { cpu_request = "175m", cpu_limit = "1000m", memory_request = "768Mi", memory_limit = "2Gi", storage = "16Gi", redis_maxmemory = "" }
      redis      = { cpu_request = "100m", cpu_limit = "400m", memory_request = "256Mi", memory_limit = "1Gi", storage = "4Gi", redis_maxmemory = "768mb" }
      kafka      = { cpu_request = "140m", cpu_limit = "1000m", memory_request = "768Mi", memory_limit = "2Gi", storage = "10Gi", redis_maxmemory = "" }
      influxdb   = { cpu_request = "70m", cpu_limit = "500m", memory_request = "768Mi", memory_limit = "2Gi", storage = "5Gi", redis_maxmemory = "" }
      minio      = { cpu_request = "140m", cpu_limit = "1000m", memory_request = "384Mi", memory_limit = "2Gi", storage = "20Gi", redis_maxmemory = "" }
      vault      = { cpu_request = "70m", cpu_limit = "500m", memory_request = "192Mi", memory_limit = "512Mi", storage = "", redis_maxmemory = "" }
    }
  }

  row      = local.sizes[var.environment]
  prod_row = local.sizes.prod
  dr_row   = local.sizes.dr

  cpu_m = { for name, spec in local.row : name => {
    req = endswith(spec.cpu_request, "m") ? tonumber(trimsuffix(spec.cpu_request, "m")) : tonumber(spec.cpu_request) * 1000
    lim = endswith(spec.cpu_limit, "m") ? tonumber(trimsuffix(spec.cpu_limit, "m")) : tonumber(spec.cpu_limit) * 1000
  } }

  mem_mi = { for name, spec in local.row : name => {
    req = endswith(spec.memory_request, "Gi") ? tonumber(trimsuffix(spec.memory_request, "Gi")) * 1024 : tonumber(trimsuffix(spec.memory_request, "Mi"))
    lim = endswith(spec.memory_limit, "Gi") ? tonumber(trimsuffix(spec.memory_limit, "Gi")) * 1024 : tonumber(trimsuffix(spec.memory_limit, "Mi"))
  } }

  redis_max_mi     = local.row.redis.redis_maxmemory == "" ? 0 : tonumber(replace(replace(local.row.redis.redis_maxmemory, "mb", ""), "Mi", ""))
  redis_limit_cap  = floor(local.mem_mi["redis"].lim * 75 / 100)
  cpu_ok           = alltrue([for n, v in local.cpu_m : v.req <= v.lim && v.req >= 50])
  mem_ok           = alltrue([for n, v in local.mem_mi : v.req <= v.lim])
  redis_ok         = local.redis_max_mi > 0 ? local.redis_max_mi <= local.redis_limit_cap : true
  dr_limits_eq     = alltrue([for n, spec in local.dr_row : spec.cpu_limit == local.prod_row[n].cpu_limit && spec.memory_limit == local.prod_row[n].memory_limit])
  cpu_m_prod = { for name, spec in local.prod_row : name => endswith(spec.cpu_request, "m") ? tonumber(trimsuffix(spec.cpu_request, "m")) : tonumber(spec.cpu_request) * 1000 }
  cpu_m_dr   = { for name, spec in local.dr_row : name => endswith(spec.cpu_request, "m") ? tonumber(trimsuffix(spec.cpu_request, "m")) : tonumber(spec.cpu_request) * 1000 }
  mem_mi_prod = { for name, spec in local.prod_row : name => endswith(spec.memory_request, "Gi") ? tonumber(trimsuffix(spec.memory_request, "Gi")) * 1024 : tonumber(trimsuffix(spec.memory_request, "Mi")) }
  mem_mi_dr   = { for name, spec in local.dr_row : name => endswith(spec.memory_request, "Gi") ? tonumber(trimsuffix(spec.memory_request, "Gi")) * 1024 : tonumber(trimsuffix(spec.memory_request, "Mi")) }
  prod_req_ge_dr = alltrue([for n, v in local.cpu_m_prod : v >= local.cpu_m_dr[n]]) && alltrue([for n, v in local.mem_mi_prod : v >= local.mem_mi_dr[n]])
}

check "request_le_limit" {
  assert {
    condition     = local.cpu_ok && local.mem_ok && local.redis_ok
    error_message = "store-sizing: CPU/memory request must be ≤ limit, CPU request ≥ 50m, Redis maxmemory ≤ 75% of memory limit."
  }
}

check "dr_limits_match_prod" {
  assert {
    condition     = local.dr_limits_eq
    error_message = "store-sizing: DR limits must equal prod limits."
  }
}

check "prod_requests_ge_dr" {
  assert {
    condition     = local.prod_req_ge_dr
    error_message = "store-sizing: prod CPU/memory requests must be ≥ DR (Redis may be equal)."
  }
}
