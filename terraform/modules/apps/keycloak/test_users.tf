# Test personas for domain OIDC verify. Passwords via outputs → Vault only (never git).

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
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KC_ADMIN    = var.admin_user
      KC_PASSWORD = random_password.admin.result
      REALM       = var.realm_name
      ADMIN_USER  = "am-admin-test"
      ADMIN_PASS  = random_password.test_admin[0].result
      USER_USER   = "am-user-test"
      USER_PASS   = random_password.test_user[0].result
      ADMIN_ROLES = "admin,ops,am-admin,am-ops"
      USER_ROLES  = "user,am-user"
      NODE_PORT   = tostring(var.node_port)
      ENV_NAME    = var.environment
      SCRIPT      = "${path.module}/scripts/configure_test_users.py"
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

  depends_on = [null_resource.realm_and_clients]
}

output "test_user_passwords" {
  description = "Map username → password for Vault. Never commit."
  value = var.manage_realm && var.create_test_users ? {
    "am-admin-test" = random_password.test_admin[0].result
    "am-user-test"  = random_password.test_user[0].result
  } : {}
  sensitive = true
}
