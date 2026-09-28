# Test personas for domain OIDC verify. Passwords via outputs â†’ Vault only (never git).

resource "random_password" "test_admin" {
  count   = var.manage_realm && var.create_test_users ? 1 : 0
  length  = 24
  special = false
}

resource "random_password" "test_user" {
  count   = var.manage_realm && var.create_test_users ? 1 : 0
  length  = 24
  special = false
}

resource "null_resource" "test_users" {
  count = var.manage_realm && var.create_test_users ? 1 : 0

  triggers = {
    realm_id    = null_resource.realm_and_clients[0].id
    admin_pw    = random_password.test_admin[0].result
    user_pw     = random_password.test_user[0].result
    script_hash = filesha256("${path.module}/scripts/configure_test_users.py")
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      KC_ADMIN    = var.admin_user
      KC_PASSWORD = random_password.admin.result
      REALM       = var.realm_name
      ADMIN_USER  = "am-admin-test"
      ADMIN_PASS  = random_password.test_admin[0].result
      USER_USER   = "am-user-test"
      USER_PASS   = random_password.test_user[0].result
      ADMIN_ROLES = "am-admin,am-ops"
      USER_ROLES  = "am-user"
      NODE_PORT   = tostring(var.node_port)
      ENV_NAME    = var.environment
      KIND_ROLE   = var.gateway_same_cluster ? "infra" : "platform"
      SCRIPT      = "${path.module}/scripts/configure_test_users.py"
    }
    command = <<-BASH
      set -euo pipefail
      NODE="am-$${ENV_NAME}-$${KIND_ROLE}-control-plane"
      IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NODE" | awk '{print $1}')
      test -n "$IP"
      PF_PORT=18081
      PF_PID=""
      cleanup() { if [ -n "$PF_PID" ]; then kill "$PF_PID" 2>/dev/null || true; fi; }
      trap cleanup EXIT
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
        kubectl --kubeconfig "$KCFG" -n identity port-forward svc/keycloak "$${PF_PORT}:8080" >/tmp/kc-pf-users.log 2>&1 &
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

  depends_on = [null_resource.realm_and_clients]
}

output "test_user_passwords" {
  description = "Map username â†’ password for Vault. Never commit."
  value = var.manage_realm && var.create_test_users ? {
    "am-admin-test" = random_password.test_admin[0].result
    "am-user-test"  = random_password.test_user[0].result
  } : {}
  sensitive = true
}
