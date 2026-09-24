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
    realm_id = null_resource.realm_and_clients[0].id
    admin_pw = random_password.test_admin[0].result
    user_pw  = random_password.test_user[0].result
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    environment = {
      KUBECONFIG  = pathexpand("~/.asrax/kubeconfig.am-${var.environment}-platform.yaml")
      KC_NS       = var.namespace
      KC_ADMIN    = var.admin_user
      KC_PASSWORD = random_password.admin.result
      REALM       = var.realm_name
      ADMIN_USER  = "am-admin-test"
      ADMIN_PASS  = random_password.test_admin[0].result
      USER_USER   = "am-user-test"
      USER_PASS   = random_password.test_user[0].result
      ADMIN_ROLES = "admin,ops,am-admin,am-ops"
      USER_ROLES  = "user,am-user"
    }
    command = <<-PS
      $ErrorActionPreference = 'Stop'
      $pf = Start-Process -FilePath kubectl -ArgumentList @('--kubeconfig', $env:KUBECONFIG, '-n', $env:KC_NS, 'port-forward', 'svc/keycloak', '18081:8080') -PassThru -WindowStyle Hidden
      try {
        $base = 'http://127.0.0.1:18081'
        $tokenBody = @{
          grant_type = 'password'
          client_id  = 'admin-cli'
          username   = $env:KC_ADMIN
          password   = $env:KC_PASSWORD
        }
        $tok = $null
        for ($i = 0; $i -lt 60; $i++) {
          try {
            $tok = Invoke-RestMethod -Method Post -Uri "$base/realms/master/protocol/openid-connect/token" -Body $tokenBody -ContentType 'application/x-www-form-urlencoded'
            break
          } catch { Start-Sleep 5 }
        }
        if (-not $tok) { throw "Keycloak admin token failed for test users" }
        $h = @{ Authorization = "Bearer $($tok.access_token)"; 'Content-Type' = 'application/json' }
        $realm = $env:REALM

        function Ensure-User($username, $password, $roleCsv) {
          $found = Invoke-RestMethod -Method Get -Uri "$base/admin/realms/$realm/users?username=$username&exact=true" -Headers $h
          $uid = $null
          if ($found -and $found.Count -gt 0) {
            $uid = $found[0].id
            $upd = @{ enabled = $true; emailVerified = $true; email = "$username@asrax.in"; firstName = $username; lastName = 'test'; requiredActions = @() } | ConvertTo-Json
            Invoke-RestMethod -Method Put -Uri "$base/admin/realms/$realm/users/$uid" -Headers $h -Body $upd | Out-Null
          } else {
            $body = @{
              username        = $username
              enabled         = $true
              emailVerified   = $true
              email           = "$username@asrax.in"
              firstName       = $username
              lastName        = 'test'
              requiredActions = @()
              credentials     = @(@{ type = 'password'; value = $password; temporary = $false })
            } | ConvertTo-Json -Depth 5
            Invoke-RestMethod -Method Post -Uri "$base/admin/realms/$realm/users" -Headers $h -Body $body | Out-Null
            $found = Invoke-RestMethod -Method Get -Uri "$base/admin/realms/$realm/users?username=$username&exact=true" -Headers $h
            $uid = $found[0].id
          }
          $pwBody = @{ type = 'password'; value = $password; temporary = $false } | ConvertTo-Json
          Invoke-RestMethod -Method Put -Uri "$base/admin/realms/$realm/users/$uid/reset-password" -Headers $h -Body $pwBody | Out-Null
          foreach ($role in ($roleCsv -split ',')) {
            $role = $role.Trim()
            if (-not $role) { continue }
            $roleObj = Invoke-RestMethod -Method Get -Uri "$base/admin/realms/$realm/roles/$role" -Headers $h
            $mapBody = (@($roleObj) | ConvertTo-Json -Depth 5)
            if ($mapBody -notmatch '^\[') { $mapBody = "[$mapBody]" }
            try {
              Invoke-RestMethod -Method Post -Uri "$base/admin/realms/$realm/users/$uid/role-mappings/realm" -Headers $h -Body $mapBody | Out-Null
            } catch { }
          }
          Write-Output "user_ok=$username"
        }

        Ensure-User $env:ADMIN_USER $env:ADMIN_PASS $env:ADMIN_ROLES
        Ensure-User $env:USER_USER $env:USER_PASS $env:USER_ROLES
      } finally {
        if ($pf -and -not $pf.HasExited) { Stop-Process -Id $pf.Id -Force -ErrorAction SilentlyContinue }
      }
    PS
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
