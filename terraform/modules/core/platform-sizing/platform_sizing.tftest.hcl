run "dev_keycloak" {
  command = plan
  variables {
    environment = "dev"
  }
  assert {
    condition     = output.keycloak.cpu_request == "250m" && output.keycloak.memory_limit == "1Gi"
    error_message = "dev Keycloak must be 250m → 1000m / 768Mi → 1Gi"
  }
}

run "dev_novu_api" {
  command = plan
  variables {
    environment = "dev"
  }
  assert {
    condition     = output.novu_api.cpu_request == "50m" && output.novu_api.memory_limit == "512Mi"
    error_message = "dev Novu api must request 50m and limit 512Mi"
  }
}

run "prod_argocd_controller" {
  command = plan
  variables {
    environment = "prod"
  }
  assert {
    condition     = output.argocd_controller.cpu_request == "200m" && output.argocd_controller.memory_limit == "1Gi"
    error_message = "prod Argo controller request 200m limit mem 1Gi"
  }
}

run "dr_limits_match_prod_keycloak" {
  command = plan
  variables {
    environment = "dr"
  }
  assert {
    condition     = output.keycloak.cpu_limit == "1000m" && output.keycloak.memory_limit == "2Gi" && output.keycloak.cpu_request == "350m"
    error_message = "DR Keycloak limits must match prod; request must be lower"
  }
}

run "dr_novu_limits_eq_prod" {
  command = plan
  variables {
    environment = "dr"
  }
  assert {
    condition = (
      output.novu_api.cpu_limit == "500m" && output.novu_api.memory_limit == "512Mi" &&
      output.novu_web.cpu_limit == "250m" && output.novu_web.memory_limit == "256Mi"
    )
    error_message = "DR Novu limits must equal prod"
  }
}
