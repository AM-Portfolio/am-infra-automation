# G24 OIDC clients in am-realm. Redirects = https://*.asrax.in only. Secrets via outputs → Vault at root.

locals {
  host = local.auth_host
  # prod: name.asrax.in; else name-<env>.asrax.in (am / auth special-cased in PLAN)
  ui = {
    for name in [
      "am-modern-ui",
      "am-gateway",
      "minio",
      "grafana",
      "argocd",
      "headlamp",
      "kafka-ui",
      "pgadmin",
      "mongo-express",
      "redis-ui",
      "vault-ui",
      "influx-ui",
      "temporal-web",
      "lago",
      "n8n",
      "growthbook",
      "openproject",
      "litellm",
      "langfuse",
      "traefik",
      "novu",
    ] : name => name
  }

  # Host labels for redirect URLs (client id → DNS label)
  redirect_host = {
    "am-modern-ui"  = var.environment == "prod" ? "am" : "am-${var.environment}"
    "am-gateway"    = var.environment == "prod" ? "am" : "am-${var.environment}"
    "minio"         = var.environment == "prod" ? "minio" : "minio-${var.environment}"
    "grafana"       = "grafana"
    "argocd"        = var.environment == "prod" ? "argocd" : "argocd-${var.environment}"
    "headlamp"      = var.environment == "prod" ? "headlamp" : "headlamp-${var.environment}"
    "kafka-ui"      = "kafka-ui${local.domain_suffix}"
    "pgadmin"       = "pgadmin${local.domain_suffix}"
    "mongo-express" = "mongo-express${local.domain_suffix}"
    "redis-ui"      = "redis-ui${local.domain_suffix}"
    "vault-ui"      = "vault${local.domain_suffix}"
    "influx-ui"     = "influx${local.domain_suffix}"
    "temporal-web"  = "temporal${local.domain_suffix}"
    "lago"          = "lago${local.domain_suffix}"
    "n8n"           = "n8n${local.domain_suffix}"
    "growthbook"    = "growthbook${local.domain_suffix}"
    "openproject"   = "openproject${local.domain_suffix}"
    "litellm"       = "litellm${local.domain_suffix}"
    "langfuse"      = "langfuse${local.domain_suffix}"
    "traefik"       = "traefik${local.domain_suffix}"
    "novu"          = "novu${local.domain_suffix}"
  }
}

resource "random_password" "oidc_secret" {
  for_each = var.manage_realm ? local.ui : {}
  length   = 32
  special  = false
}

# Realm + clients via Keycloak Admin API after Helm is Ready (no Authentik).
# Uses platform NodePort on kind Docker IP (works on VPS Linux; no PowerShell / no port-forward).
resource "null_resource" "realm_and_clients" {
  count = var.manage_realm ? 1 : 0

  triggers = {
    keycloak_revision = helm_release.keycloak.id
    clients_hash      = sha256(jsonencode(local.redirect_host))
    mfa_enforce       = tostring(var.mfa_enforce)
    otp_optional      = tostring(var.otp_optional_enroll)
    roles_hash        = sha256(jsonencode(var.realm_roles))
    script_hash       = filesha256("${path.module}/scripts/configure_realm.py")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KC_ADMIN     = var.admin_user
      KC_PASSWORD  = random_password.admin.result
      REALM        = var.realm_name
      MFA_ENFORCE  = var.mfa_enforce ? "true" : "false"
      OTP_OPTIONAL = var.otp_optional_enroll ? "true" : "false"
      NODE_PORT    = tostring(var.node_port)
      ENV_NAME     = var.environment
      CLIENTS_JSON = jsonencode([
        for id, host in local.redirect_host : {
          clientId     = id
          secret       = random_password.oidc_secret[id].result
          redirectUris = ["https://${host}.${var.root_domain}/*"]
          webOrigins   = ["https://${host}.${var.root_domain}"]
        }
      ])
      ROLES_JSON = jsonencode(var.realm_roles)
      SCRIPT     = "${path.module}/scripts/configure_realm.py"
    }
    command = <<-BASH
      set -euo pipefail
      NODE="am-$${ENV_NAME}-platform-control-plane"
      IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NODE" | awk '{print $1}')
      test -n "$IP"
      export KC_BASE="http://$${IP}:$${NODE_PORT}"
      python3 "$SCRIPT"
    BASH
  }

  depends_on = [helm_release.keycloak]
}

output "oidc_client_secrets" {
  description = "Map clientId → secret. Write to Vault; never commit."
  value       = var.manage_realm ? { for k, p in random_password.oidc_secret : k => p.result } : {}
  sensitive   = true
}

output "realm_name" { value = var.realm_name }
output "issuer_url" { value = "https://${local.auth_host}/realms/${var.realm_name}" }
