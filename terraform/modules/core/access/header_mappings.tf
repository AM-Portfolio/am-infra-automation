# ------------------------------------------------------------------------------
# Authentik Property Mappings — Header Injection
# ------------------------------------------------------------------------------

# 🛠️ Mongo Express — Basic Auth Injection
# ------------------------------------------------------------------------------
resource "authentik_scope_mapping" "mongo_basic_auth" {
  name       = "mongo-basic-auth-injection"
  scope_name = "ak_proxy"
  expression = <<-PYTHON
    return {
        "http_helpers": {
            "custom_headers": {
                "Authorization": "Basic bXVuLXJvb3QtYWRtaW46MjJNbmdoRHI1NWlPUW1u" # mun-root-admin:22MnghDr55iOQmn
            }
        }
    }
  PYTHON
}

# 🛠️ Redis Commander — Basic Auth Injection
# ------------------------------------------------------------------------------
resource "authentik_scope_mapping" "redis_basic_auth" {
  name       = "redis-basic-auth-injection"
  scope_name = "ak_proxy"
  expression = <<-PYTHON
    return {
        "http_helpers": {
            "custom_headers": {
                "Authorization": "Basic Om11bi1yZWRpcy1wYXNz" # :mun-redis-pass (Empty user + password)
            }
        }
    }
  PYTHON
}
# 🛠️ InfluxDB — Token Injection
# ------------------------------------------------------------------------------
# Secret is managed in Vault (data.vault_kv_secret_v2.databases is shared in this module)
resource "authentik_scope_mapping" "influx_token_auth" {
  name       = "influx-token-injection"
  scope_name = "ak_proxy"
  expression = <<-PYTHON
    return {
        "http_helpers": {
            "custom_headers": {
                "Authorization": "Basic ${base64encode("admin:${data.vault_kv_secret_v2.databases.data["influxdb_password"]}")}"
            }
        }
    }
  PYTHON
}
