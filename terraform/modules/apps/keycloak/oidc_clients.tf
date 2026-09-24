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
resource "null_resource" "realm_and_clients" {
  count = var.manage_realm ? 1 : 0

  triggers = {
    keycloak_revision = helm_release.keycloak.id
    clients_hash      = sha256(jsonencode(local.redirect_host))
    mfa_enforce       = tostring(var.mfa_enforce)
    otp_optional      = tostring(var.otp_optional_enroll)
    roles_hash        = sha256(jsonencode(var.realm_roles))
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    environment = {
      KUBECONFIG  = pathexpand("~/.asrax/kubeconfig.am-${var.environment}-platform.yaml")
      KC_NS       = var.namespace
      KC_ADMIN    = var.admin_user
      KC_PASSWORD = random_password.admin.result
      REALM       = var.realm_name
      ROOT_DOMAIN = var.root_domain
      MFA_ENFORCE = var.mfa_enforce ? "true" : "false"
      OTP_OPTIONAL = var.otp_optional_enroll ? "true" : "false"
      CLIENTS_JSON = jsonencode([
        for id, host in local.redirect_host : {
          clientId     = id
          secret       = random_password.oidc_secret[id].result
          redirectUris = ["https://${host}.${var.root_domain}/*"]
          webOrigins   = ["https://${host}.${var.root_domain}"]
        }
      ])
      ROLES_JSON = jsonencode(var.realm_roles)
    }
    command = <<-PS
      $ErrorActionPreference = 'Stop'
      $pf = Start-Process -FilePath kubectl -ArgumentList @('--kubeconfig', $env:KUBECONFIG, '-n', $env:KC_NS, 'port-forward', 'svc/keycloak', '18080:8080') -PassThru -WindowStyle Hidden
      try {
        $base = 'http://127.0.0.1:18080'
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
        if (-not $tok) { throw "Keycloak admin token failed" }
        $h = @{ Authorization = "Bearer $($tok.access_token)"; 'Content-Type' = 'application/json' }
        $realm = $env:REALM
        try { Invoke-RestMethod -Method Get -Uri "$base/admin/realms/$realm" -Headers $h | Out-Null }
        catch {
          $realmBody = @{ realm = $realm; enabled = $true; displayName = 'AM Realm'; sslRequired = 'external' } | ConvertTo-Json
          Invoke-RestMethod -Method Post -Uri "$base/admin/realms" -Headers $h -Body $realmBody | Out-Null
        }
        foreach ($role in ($env:ROLES_JSON | ConvertFrom-Json)) {
          try { Invoke-RestMethod -Method Get -Uri "$base/admin/realms/$realm/roles/$role" -Headers $h | Out-Null }
          catch {
            $rb = @{ name = $role } | ConvertTo-Json
            Invoke-RestMethod -Method Post -Uri "$base/admin/realms/$realm/roles" -Headers $h -Body $rb | Out-Null
          }
        }
        # Default role for new users = user (canonical)
        try {
          $defs = Invoke-RestMethod -Method Get -Uri "$base/admin/realms/$realm/default-roles/$realm" -Headers $h -ErrorAction SilentlyContinue
        } catch { $defs = $null }
        try {
          $userRole = Invoke-RestMethod -Method Get -Uri "$base/admin/realms/$realm/roles/user" -Headers $h
          $defBody = @(@{ id = $userRole.id; name = 'user' }) | ConvertTo-Json -Depth 5
          Invoke-RestMethod -Method Post -Uri "$base/admin/realms/$realm/roles-by-id/$($userRole.id)/composites" -Headers $h -Body '[]' -ErrorAction SilentlyContinue | Out-Null
        } catch { Write-Output "default_role_hint_skipped" }

        # OTP: enable required action CONFIGURE_TOTP (optional until MFA_ENFORCE)
        try {
          $ra = Invoke-RestMethod -Method Get -Uri "$base/admin/realms/$realm/authentication/required-actions/CONFIGURE_TOTP" -Headers $h
          $ra.enabled = ($env:OTP_OPTIONAL -eq 'true' -or $env:MFA_ENFORCE -eq 'true')
          $ra.defaultAction = ($env:MFA_ENFORCE -eq 'true')
          Invoke-RestMethod -Method Put -Uri "$base/admin/realms/$realm/authentication/required-actions/CONFIGURE_TOTP" -Headers $h -Body ($ra | ConvertTo-Json -Depth 5) | Out-Null
        } catch { Write-Output "configure_totp_skipped: $_" }

        if ($env:MFA_ENFORCE -eq 'true') {
          # Bind browser flow copy with OTP as required — best-effort via realm otpPolicy
          $r = Invoke-RestMethod -Method Get -Uri "$base/admin/realms/$realm" -Headers $h
          $r.otpPolicyType = 'totp'
          $r.otpPolicyAlgorithm = 'HmacSHA1'
          $r.otpPolicyDigits = 6
          $r.otpPolicyPeriod = 30
          Invoke-RestMethod -Method Put -Uri "$base/admin/realms/$realm" -Headers $h -Body ($r | ConvertTo-Json -Depth 8) | Out-Null
        }

        $directGrants = if ($env:MFA_ENFORCE -eq 'true') { $false } else { $true }
        $clients = $env:CLIENTS_JSON | ConvertFrom-Json
        foreach ($c in $clients) {
          $existing = Invoke-RestMethod -Method Get -Uri "$base/admin/realms/$realm/clients?clientId=$($c.clientId)" -Headers $h
          $payload = @{
            clientId                  = $c.clientId
            enabled                   = $true
            protocol                  = 'openid-connect'
            publicClient              = $false
            secret                    = $c.secret
            redirectUris              = @($c.redirectUris)
            webOrigins                = @($c.webOrigins)
            standardFlowEnabled       = $true
            directAccessGrantsEnabled = $directGrants
            attributes                = @{ 'post.logout.redirect.uris' = ($c.redirectUris -join '##') }
          } | ConvertTo-Json -Depth 5
          if ($existing -and $existing.Count -gt 0) {
            $id = $existing[0].id
            Invoke-RestMethod -Method Put -Uri "$base/admin/realms/$realm/clients/$id" -Headers $h -Body $payload | Out-Null
          } else {
            Invoke-RestMethod -Method Post -Uri "$base/admin/realms/$realm/clients" -Headers $h -Body $payload | Out-Null
          }
        }
        Write-Output "realm_ok=$realm clients=$($clients.Count) mfa_enforce=$($env:MFA_ENFORCE) direct_grants=$directGrants"
      } finally {
        if ($pf -and -not $pf.HasExited) { Stop-Process -Id $pf.Id -Force -ErrorAction SilentlyContinue }
      }
    PS
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
