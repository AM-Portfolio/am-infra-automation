# Static contracts for apps-vault-seed (no live Vault required).
#   terraform -chdir=terraform/modules/core/apps-vault-seed init -backend=false
#   terraform -chdir=terraform/modules/core/apps-vault-seed test

provider "vault" {
  address = "http://127.0.0.1:8200"
  token   = "s.test-not-used-for-plan-asserts"
}

run "prod_identity_uses_real_admin_password" {
  command = plan
  variables {
    env                     = "prod"
    domain                  = "asrax.in"
    postgres_user           = "postgres"
    postgres_password       = "pg-test-pass-xxxxxxxx"
    mongo_user              = "admin"
    mongo_password          = "mongo-test-pass-xxxxxx"
    redis_password          = "redis-test-pass-xxxxxx"
    influx_token            = "influx-token-xxxxxxxxxx"
    influx_org              = "am"
    influx_bucket           = "metrics"
    keycloak_admin_user     = "admin"
    keycloak_admin_password = "real-kc-admin-password-24"
  }

  assert {
    condition = (
      output.identity_keycloak_admin_user == "admin" &&
      output.identity_oidc_issuer == "https://auth.asrax.in/realms/am-realm" &&
      !endswith(output.identity_oidc_issuer, ":30808/realms/am-realm")
    )
    error_message = "prod identity must use auth.asrax.in issuer and wired admin user"
  }

  assert {
    condition     = contains(output.service_names, "am-identity")
    error_message = "am-identity must be in catalog seed"
  }

  assert {
    condition     = contains(output.service_names, "am-fin-agent")
    error_message = "am-fin-agent must be in catalog seed"
  }
}

run "dev_hosts_use_env_suffix" {
  command = plan
  variables {
    env                     = "dev"
    domain                  = "asrax.in"
    postgres_user           = "postgres"
    postgres_password       = "pg-test-pass-xxxxxxxx"
    mongo_user              = "admin"
    mongo_password          = "mongo-test-pass-xxxxxx"
    redis_password          = "redis-test-pass-xxxxxx"
    influx_token            = "influx-token-xxxxxxxxxx"
    influx_org              = "am"
    influx_bucket           = "metrics"
    keycloak_admin_user     = "admin"
    keycloak_admin_password = "real-kc-admin-password-24"
  }

  assert {
    condition     = output.identity_oidc_issuer == "https://auth-dev.asrax.in/realms/am-realm"
    error_message = "dev OIDC issuer must be auth-dev.asrax.in"
  }
}

run "empty_admin_password_fails" {
  command = plan
  variables {
    env                     = "prod"
    domain                  = "asrax.in"
    postgres_user           = "postgres"
    postgres_password       = "pg-test-pass-xxxxxxxx"
    mongo_user              = "admin"
    mongo_password          = "mongo-test-pass-xxxxxx"
    redis_password          = "redis-test-pass-xxxxxx"
    influx_token            = "influx-token-xxxxxxxxxx"
    influx_org              = "am"
    influx_bucket           = "metrics"
    keycloak_admin_password = ""
  }

  expect_failures = [
    terraform_data.require_keycloak_admin,
  ]
}
