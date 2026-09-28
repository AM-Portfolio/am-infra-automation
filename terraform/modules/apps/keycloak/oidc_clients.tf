# G24 OIDC clients in am-realm. Redirects = https://*.asrax.in only. Secrets via outputs â†’ Vault at root.

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

  # kubectl / oidc-login — localhost callbacks only (CLI)
  kubectl_redirects = [
    "http://localhost:8000",
    "http://localhost:8000/callback",
    "http://127.0.0.1:8000/callback",
    "http://localhost:18000",
    "http://localhost:18000/callback",
  ]

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
# Hits Kind NodePort on docker IP: platform Kind by default; infra Kind when gateway_same_cluster.
resource "null_resource" "realm_and_clients" {
  count = var.manage_realm ? 1 : 0

  triggers = {
    keycloak_revision = helm_release.keycloak.id
    clients_hash      = sha256(jsonencode(local.redirect_host))
    mfa_enforce       = tostring(var.mfa_enforce)
    otp_optional      = tostring(var.otp_optional_enroll)
    roles_hash        = sha256(jsonencode(var.realm_roles))
    script_hash       = filesha256("${path.module}/scripts/configure_realm.py")
    kind_role         = var.gateway_same_cluster ? "infra" : "platform"
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      KC_ADMIN     = var.admin_user
      KC_PASSWORD  = random_password.admin.result
      REALM        = var.realm_name
      MFA_ENFORCE  = var.mfa_enforce ? "true" : "false"
      OTP_OPTIONAL = var.otp_optional_enroll ? "true" : "false"
      NODE_PORT    = tostring(var.node_port)
      ENV_NAME     = var.environment
      KIND_ROLE    = var.gateway_same_cluster ? "infra" : "platform"
      CLIENTS_JSON = jsonencode(concat(
        [
          for id, host in local.redirect_host : {
            clientId     = id
            secret       = random_password.oidc_secret[id].result
            redirectUris = ["https://${host}.${var.root_domain}/*"]
            webOrigins   = ["https://${host}.${var.root_domain}"]
            publicClient = false
          }
        ],
        [
          {
            clientId     = "kubectl"
            secret       = ""
            redirectUris = local.kubectl_redirects
            webOrigins   = ["+"]
            publicClient = true
          }
        ]
      ))
      ROLES_JSON = jsonencode(var.realm_roles)
      SCRIPT     = "${path.module}/scripts/configure_realm.py"
    }
    command = <<-BASH
      set -euo pipefail
      NODE="am-$${ENV_NAME}-$${KIND_ROLE}-control-plane"
      IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NODE" | awk '{print $1}')
      test -n "$IP"
      PF_PORT=18080
      PF_PID=""
      cleanup() { if [ -n "$PF_PID" ]; then kill "$PF_PID" 2>/dev/null || true; fi; }
      trap cleanup EXIT
      # Windows/WSL2: host often cannot reach Kind NodePort on docker IP — use kubectl PF.
      if command -v curl >/dev/null 2>&1 && curl -sf --max-time 2 "http://$${IP}:$${NODE_PORT}/" >/dev/null 2>&1; then
        export KC_BASE="http://$${IP}:$${NODE_PORT}"
      else
        KCFG="$${KUBECONFIG:-}"
        if [ -z "$KCFG" ]; then
          KCFG="$HOME/.asrax/kubeconfig.am-$${ENV_NAME}-$${KIND_ROLE}.yaml"
        fi
        if [ ! -f "$KCFG" ] && [ -f "/c/Users/$USER/.asrax/kubeconfig.am-$${ENV_NAME}-$${KIND_ROLE}.yaml" ]; then
          KCFG="/c/Users/$USER/.asrax/kubeconfig.am-$${ENV_NAME}-$${KIND_ROLE}.yaml"
        fi
        test -f "$KCFG"
        kubectl --kubeconfig "$KCFG" -n identity port-forward svc/keycloak "$${PF_PORT}:8080" >/tmp/kc-pf-realm.log 2>&1 &
        PF_PID=$!
        i=0
        while [ "$i" -lt 45 ]; do
          if curl -sf --max-time 1 "http://127.0.0.1:$${PF_PORT}/" >/dev/null 2>&1; then
            break
          fi
          i=$((i + 1))
          sleep 1
        done
        export KC_BASE="http://127.0.0.1:$${PF_PORT}"
      fi
      python3 "$SCRIPT"
    BASH
  }

  depends_on = [helm_release.keycloak]
}

output "oidc_client_secrets" {
  description = "Map clientId â†’ secret. Write to Vault; never commit."
  value       = var.manage_realm ? { for k, p in random_password.oidc_secret : k => p.result } : {}
  sensitive   = true
}

output "realm_name" { value = var.realm_name }
output "issuer_url" { value = "https://${local.auth_host}/realms/${var.realm_name}" }
