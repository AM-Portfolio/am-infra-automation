# Evidence-based platform CPU/memory. Module defaults elsewhere = this dev row.
# DR limits = prod; DR requests ~70% of prod. CPU request always >= 50m.

locals {
  sizes = {
    dev = {
      keycloak              = { cpu_request = "250m", cpu_limit = "1000m", memory_request = "768Mi", memory_limit = "1Gi" }
      argocd_server         = { cpu_request = "50m", cpu_limit = "500m", memory_request = "128Mi", memory_limit = "512Mi" }
      argocd_controller     = { cpu_request = "100m", cpu_limit = "1000m", memory_request = "256Mi", memory_limit = "1Gi" }
      argocd_repo_server    = { cpu_request = "50m", cpu_limit = "500m", memory_request = "128Mi", memory_limit = "512Mi" }
      temporal_server       = { cpu_request = "100m", cpu_limit = "500m", memory_request = "256Mi", memory_limit = "1Gi" }
      temporal_web          = { cpu_request = "50m", cpu_limit = "200m", memory_request = "128Mi", memory_limit = "256Mi" }
      lago_api              = { cpu_request = "200m", cpu_limit = "1000m", memory_request = "512Mi", memory_limit = "2Gi" }
      lago_front            = { cpu_request = "50m", cpu_limit = "500m", memory_request = "256Mi", memory_limit = "1Gi" }
      n8n                   = { cpu_request = "100m", cpu_limit = "1000m", memory_request = "512Mi", memory_limit = "1536Mi" }
      growthbook_frontend   = { cpu_request = "100m", cpu_limit = "750m", memory_request = "512Mi", memory_limit = "1Gi" }
      growthbook_backend    = { cpu_request = "100m", cpu_limit = "750m", memory_request = "512Mi", memory_limit = "1Gi" }
      openproject           = { cpu_request = "100m", cpu_limit = "1000m", memory_request = "512Mi", memory_limit = "2Gi" }
      # LiteLLM OOMs under 1Gi on laptop kind (exit 137).
      litellm               = { cpu_request = "50m", cpu_limit = "1000m", memory_request = "512Mi", memory_limit = "2Gi" }
      langfuse_web          = { cpu_request = "100m", cpu_limit = "500m", memory_request = "512Mi", memory_limit = "1Gi" }
      langfuse_clickhouse   = { cpu_request = "100m", cpu_limit = "1000m", memory_request = "512Mi", memory_limit = "2Gi" }
      novu_api              = { cpu_request = "50m", cpu_limit = "500m", memory_request = "128Mi", memory_limit = "512Mi" }
      novu_worker           = { cpu_request = "50m", cpu_limit = "500m", memory_request = "128Mi", memory_limit = "512Mi" }
      novu_web              = { cpu_request = "50m", cpu_limit = "250m", memory_request = "64Mi", memory_limit = "256Mi" }
      novu_ws               = { cpu_request = "50m", cpu_limit = "250m", memory_request = "64Mi", memory_limit = "256Mi" }
    }
    prod = {
      keycloak              = { cpu_request = "500m", cpu_limit = "1000m", memory_request = "1Gi", memory_limit = "2Gi" }
      argocd_server         = { cpu_request = "100m", cpu_limit = "500m", memory_request = "256Mi", memory_limit = "512Mi" }
      argocd_controller     = { cpu_request = "200m", cpu_limit = "1000m", memory_request = "512Mi", memory_limit = "1Gi" }
      argocd_repo_server    = { cpu_request = "100m", cpu_limit = "500m", memory_request = "256Mi", memory_limit = "512Mi" }
      temporal_server       = { cpu_request = "250m", cpu_limit = "1000m", memory_request = "512Mi", memory_limit = "2Gi" }
      temporal_web          = { cpu_request = "100m", cpu_limit = "500m", memory_request = "256Mi", memory_limit = "512Mi" }
      lago_api              = { cpu_request = "500m", cpu_limit = "2000m", memory_request = "1Gi", memory_limit = "4Gi" }
      lago_front            = { cpu_request = "200m", cpu_limit = "1000m", memory_request = "512Mi", memory_limit = "2Gi" }
      n8n                   = { cpu_request = "250m", cpu_limit = "1000m", memory_request = "1Gi", memory_limit = "2Gi" }
      growthbook_frontend   = { cpu_request = "200m", cpu_limit = "1000m", memory_request = "512Mi", memory_limit = "2Gi" }
      growthbook_backend    = { cpu_request = "200m", cpu_limit = "1000m", memory_request = "512Mi", memory_limit = "2Gi" }
      openproject           = { cpu_request = "250m", cpu_limit = "1000m", memory_request = "1Gi", memory_limit = "2Gi" }
      litellm               = { cpu_request = "200m", cpu_limit = "1000m", memory_request = "512Mi", memory_limit = "2Gi" }
      langfuse_web          = { cpu_request = "200m", cpu_limit = "1000m", memory_request = "512Mi", memory_limit = "2Gi" }
      langfuse_clickhouse   = { cpu_request = "250m", cpu_limit = "1000m", memory_request = "1Gi", memory_limit = "2Gi" }
      novu_api              = { cpu_request = "100m", cpu_limit = "500m", memory_request = "256Mi", memory_limit = "512Mi" }
      novu_worker           = { cpu_request = "100m", cpu_limit = "500m", memory_request = "256Mi", memory_limit = "512Mi" }
      novu_web              = { cpu_request = "50m", cpu_limit = "250m", memory_request = "128Mi", memory_limit = "256Mi" }
      novu_ws               = { cpu_request = "50m", cpu_limit = "250m", memory_request = "128Mi", memory_limit = "256Mi" }
    }
    dr = {
      keycloak              = { cpu_request = "350m", cpu_limit = "1000m", memory_request = "768Mi", memory_limit = "2Gi" }
      argocd_server         = { cpu_request = "70m", cpu_limit = "500m", memory_request = "192Mi", memory_limit = "512Mi" }
      argocd_controller     = { cpu_request = "140m", cpu_limit = "1000m", memory_request = "384Mi", memory_limit = "1Gi" }
      argocd_repo_server    = { cpu_request = "70m", cpu_limit = "500m", memory_request = "192Mi", memory_limit = "512Mi" }
      temporal_server       = { cpu_request = "175m", cpu_limit = "1000m", memory_request = "384Mi", memory_limit = "2Gi" }
      temporal_web          = { cpu_request = "70m", cpu_limit = "500m", memory_request = "192Mi", memory_limit = "512Mi" }
      lago_api              = { cpu_request = "350m", cpu_limit = "2000m", memory_request = "768Mi", memory_limit = "4Gi" }
      lago_front            = { cpu_request = "140m", cpu_limit = "1000m", memory_request = "384Mi", memory_limit = "2Gi" }
      n8n                   = { cpu_request = "175m", cpu_limit = "1000m", memory_request = "768Mi", memory_limit = "2Gi" }
      growthbook_frontend   = { cpu_request = "140m", cpu_limit = "1000m", memory_request = "384Mi", memory_limit = "2Gi" }
      growthbook_backend    = { cpu_request = "140m", cpu_limit = "1000m", memory_request = "384Mi", memory_limit = "2Gi" }
      openproject           = { cpu_request = "175m", cpu_limit = "1000m", memory_request = "768Mi", memory_limit = "2Gi" }
      litellm               = { cpu_request = "140m", cpu_limit = "1000m", memory_request = "384Mi", memory_limit = "2Gi" }
      langfuse_web          = { cpu_request = "140m", cpu_limit = "1000m", memory_request = "384Mi", memory_limit = "2Gi" }
      langfuse_clickhouse   = { cpu_request = "175m", cpu_limit = "1000m", memory_request = "768Mi", memory_limit = "2Gi" }
      novu_api              = { cpu_request = "70m", cpu_limit = "500m", memory_request = "192Mi", memory_limit = "512Mi" }
      novu_worker           = { cpu_request = "70m", cpu_limit = "500m", memory_request = "192Mi", memory_limit = "512Mi" }
      novu_web              = { cpu_request = "50m", cpu_limit = "250m", memory_request = "96Mi", memory_limit = "256Mi" }
      novu_ws               = { cpu_request = "50m", cpu_limit = "250m", memory_request = "96Mi", memory_limit = "256Mi" }
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

  cpu_ok = alltrue([for n, v in local.cpu_m : v.req <= v.lim && v.req >= 50])
  mem_ok = alltrue([for n, v in local.mem_mi : v.req <= v.lim])

  dr_limits_eq = alltrue([for n, spec in local.dr_row : spec.cpu_limit == local.prod_row[n].cpu_limit && spec.memory_limit == local.prod_row[n].memory_limit])

  cpu_m_prod  = { for name, spec in local.prod_row : name => endswith(spec.cpu_request, "m") ? tonumber(trimsuffix(spec.cpu_request, "m")) : tonumber(spec.cpu_request) * 1000 }
  cpu_m_dr    = { for name, spec in local.dr_row : name => endswith(spec.cpu_request, "m") ? tonumber(trimsuffix(spec.cpu_request, "m")) : tonumber(spec.cpu_request) * 1000 }
  mem_mi_prod = { for name, spec in local.prod_row : name => endswith(spec.memory_request, "Gi") ? tonumber(trimsuffix(spec.memory_request, "Gi")) * 1024 : tonumber(trimsuffix(spec.memory_request, "Mi")) }
  mem_mi_dr   = { for name, spec in local.dr_row : name => endswith(spec.memory_request, "Gi") ? tonumber(trimsuffix(spec.memory_request, "Gi")) * 1024 : tonumber(trimsuffix(spec.memory_request, "Mi")) }
  prod_req_ge_dr = alltrue([for n, v in local.cpu_m_prod : v >= local.cpu_m_dr[n]]) && alltrue([for n, v in local.mem_mi_prod : v >= local.mem_mi_dr[n]])
}

check "request_le_limit" {
  assert {
    condition     = local.cpu_ok && local.mem_ok
    error_message = "platform-sizing: CPU/memory request must be ≤ limit and CPU request ≥ 50m."
  }
}

check "dr_limits_match_prod" {
  assert {
    condition     = local.dr_limits_eq
    error_message = "platform-sizing: DR limits must equal prod limits."
  }
}

check "prod_requests_ge_dr" {
  assert {
    condition     = local.prod_req_ge_dr
    error_message = "platform-sizing: prod CPU/memory requests must be ≥ DR."
  }
}
