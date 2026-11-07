# Configure am-dev-realm + am-preprod-realm on Contabo prod Keycloak (auth.asrax.in).
# Does NOT touch DR Keycloak. Writes secrets JSON for Vault patching.
param(
  [string] $AdminPassword = $env:KC_PASSWORD,
  [string] $DemoEmail = "munish.prime@gmail.com",
  [string] $DemoPassword = "@M1unish",
  [string] $OutFile = "$env:TEMP\kc-shared-prod-realm-secrets.json"
)
$ErrorActionPreference = "Stop"
$ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
if (-not $AdminPassword) { throw "Set KC_PASSWORD or -AdminPassword" }

function Get-KcToken {
  (Invoke-RestMethod -Method Post -Uri "https://auth.asrax.in/realms/master/protocol/openid-connect/token" `
    -Headers @{ "User-Agent" = $ua } `
    -Body @{ grant_type = "password"; client_id = "admin-cli"; username = "admin"; password = $AdminPassword } `
    -ContentType "application/x-www-form-urlencoded").access_token
}
function Hdr { @{ Authorization = "Bearer $(Get-KcToken)"; "Content-Type" = "application/json"; "User-Agent" = $ua } }
function New-Secret { -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ }) }

function Ensure-Realm([string]$realm) {
  $h = Hdr
  try {
    Invoke-RestMethod -Uri "https://auth.asrax.in/admin/realms/$realm" -Headers $h | Out-Null
    Write-Host "realm exists $realm"
  } catch {
    $body = @{
      realm = $realm; enabled = $true; displayName = $realm; sslRequired = "external"
      loginWithEmailAllowed = $true; ssoSessionIdleTimeout = 86400; ssoSessionMaxLifespan = 86400
      accessTokenLifespan = 3600
    } | ConvertTo-Json
    Invoke-RestMethod -Method Post -Uri "https://auth.asrax.in/admin/realms" -Headers $h -Body $body | Out-Null
    Write-Host "realm created $realm"
  }
}

function Ensure-Role([string]$realm, [string]$role) {
  $h = Hdr
  try { Invoke-RestMethod -Uri "https://auth.asrax.in/admin/realms/$realm/roles/$role" -Headers $h | Out-Null }
  catch {
    Invoke-RestMethod -Method Post -Uri "https://auth.asrax.in/admin/realms/$realm/roles" -Headers $h `
      -Body (@{ name = $role } | ConvertTo-Json) | Out-Null
  }
}

function Ensure-Client([string]$realm, [string]$clientId, [string]$secret, [string[]]$redirects) {
  $h = Hdr
  $existing = Invoke-RestMethod -Uri "https://auth.asrax.in/admin/realms/$realm/clients?clientId=$([uri]::EscapeDataString($clientId))" -Headers $h
  $payload = @{
    clientId = $clientId; enabled = $true; protocol = "openid-connect"; publicClient = $false; secret = $secret
    redirectUris = $redirects; webOrigins = @("*"); standardFlowEnabled = $true
    directAccessGrantsEnabled = $true; serviceAccountsEnabled = $true; fullScopeAllowed = $true
  }
  if ($existing -and @($existing).Count -gt 0) {
    $cid = $existing[0].id
    $secObj = Invoke-RestMethod -Uri "https://auth.asrax.in/admin/realms/$realm/clients/$cid/client-secret" -Headers $h
    $live = if ($secObj.value) { $secObj.value } else { $secret }
    $payload.secret = $live
    $merged = $existing[0] | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    foreach ($k in $payload.Keys) { $merged | Add-Member -NotePropertyName $k -NotePropertyValue $payload[$k] -Force }
    Invoke-RestMethod -Method Put -Uri "https://auth.asrax.in/admin/realms/$realm/clients/$cid" -Headers $h `
      -Body ($merged | ConvertTo-Json -Depth 10) | Out-Null
    return $live
  }
  Invoke-RestMethod -Method Post -Uri "https://auth.asrax.in/admin/realms/$realm/clients" -Headers $h `
    -Body ($payload | ConvertTo-Json -Depth 10) | Out-Null
  return $secret
}

function Ensure-User([string]$realm, [string]$email, [string]$password) {
  $h = Hdr
  $users = Invoke-RestMethod -Uri "https://auth.asrax.in/admin/realms/$realm/users?email=$([uri]::EscapeDataString($email))&exact=true" -Headers $h
  if (-not $users -or @($users).Count -eq 0) {
    Invoke-RestMethod -Method Post -Uri "https://auth.asrax.in/admin/realms/$realm/users" -Headers $h -Body (@{
        username = $email; email = $email; enabled = $true; emailVerified = $true; firstName = "Demo"; lastName = "User"
      } | ConvertTo-Json) | Out-Null
    $users = Invoke-RestMethod -Uri "https://auth.asrax.in/admin/realms/$realm/users?email=$([uri]::EscapeDataString($email))&exact=true" -Headers $h
  }
  $uid = $users[0].id
  $h = Hdr
  Invoke-RestMethod -Method Put -Uri "https://auth.asrax.in/admin/realms/$realm/users/$uid/reset-password" -Headers $h `
    -Body (@{ type = "password"; value = $password; temporary = $false } | ConvertTo-Json) | Out-Null
  $h = Hdr
  $avail = Invoke-RestMethod -Uri "https://auth.asrax.in/admin/realms/$realm/users/$uid/role-mappings/realm/available" -Headers $h
  $toAdd = @($avail | Where-Object { $_.name -in @("am-admin", "am-user", "am-ops") })
  if ($toAdd.Count -gt 0) {
    Invoke-RestMethod -Method Post -Uri "https://auth.asrax.in/admin/realms/$realm/users/$uid/role-mappings/realm" -Headers $h `
      -Body ($toAdd | ConvertTo-Json -Depth 5) | Out-Null
  }
}

# Mirror am-realm: users-management impersonation so am-identity-service can
# token-exchange with requested_subject (Google login). Client-level management
# permissions must stay disabled — empty token-exchange policy blocks exchange.
function Ensure-IdentityImpersonation([string]$realm) {
  $h = Hdr
  $idClients = Invoke-RestMethod -Uri "https://auth.asrax.in/admin/realms/$realm/clients?clientId=am-identity-service" -Headers $h
  if (-not $idClients -or @($idClients).Count -eq 0) { throw "am-identity-service missing in $realm" }
  $idc = $idClients[0].id

  try {
    Invoke-RestMethod -Method Put -Uri "https://auth.asrax.in/admin/realms/$realm/clients/$idc/management/permissions" `
      -Headers $h -Body '{"enabled":false}' | Out-Null
  } catch { Write-Host "warn: disable client mgmt permissions: $($_.Exception.Message)" }

  Invoke-RestMethod -Method Put -Uri "https://auth.asrax.in/admin/realms/$realm/users-management-permissions" `
    -Headers $h -Body '{"enabled":true}' | Out-Null
  $ump = Invoke-RestMethod -Uri "https://auth.asrax.in/admin/realms/$realm/users-management-permissions" -Headers $h
  $impersonatePermId = $ump.scopePermissions.impersonate
  if (-not $impersonatePermId) { throw "users impersonate permission missing in $realm" }

  $rmId = ((Invoke-RestMethod -Uri "https://auth.asrax.in/admin/realms/$realm/clients?clientId=realm-management" -Headers $h)[0]).id
  $polName = "allow-am-identity-service-impersonation"
  $existing = Invoke-RestMethod -Uri "https://auth.asrax.in/admin/realms/$realm/clients/$rmId/authz/resource-server/policy?name=$polName&permission=false" -Headers $h
  if ($existing -and @($existing).Count -gt 0) {
    $polId = $existing[0].id
    Invoke-RestMethod -Method Put -Uri "https://auth.asrax.in/admin/realms/$realm/clients/$rmId/authz/resource-server/policy/client/$polId" `
      -Headers $h -Body (@{
        id = $polId; name = $polName; type = "client"; logic = "POSITIVE"
        decisionStrategy = "UNANIMOUS"; clients = @($idc)
      } | ConvertTo-Json) | Out-Null
  } else {
    Invoke-RestMethod -Method Post -Uri "https://auth.asrax.in/admin/realms/$realm/clients/$rmId/authz/resource-server/policy/client" `
      -Headers $h -Body (@{
        name = $polName
        description = "Allow am-identity-service Google login token-exchange (requested_subject)"
        type = "client"; logic = "POSITIVE"; decisionStrategy = "UNANIMOUS"; clients = @($idc)
      } | ConvertTo-Json) | Out-Null
    Start-Sleep -Seconds 1
    $existing = Invoke-RestMethod -Uri "https://auth.asrax.in/admin/realms/$realm/clients/$rmId/authz/resource-server/policy?name=$polName&permission=false" -Headers $h
    $polId = $existing[0].id
  }

  $scopes = Invoke-RestMethod -Uri "https://auth.asrax.in/admin/realms/$realm/clients/$rmId/authz/resource-server/policy/$impersonatePermId/scopes" -Headers $h
  $resources = Invoke-RestMethod -Uri "https://auth.asrax.in/admin/realms/$realm/clients/$rmId/authz/resource-server/policy/$impersonatePermId/resources" -Headers $h
  $body = @{
    id = $impersonatePermId
    name = "admin-impersonating.permission.users"
    type = "scope"
    logic = "POSITIVE"
    decisionStrategy = "AFFIRMATIVE"
    policies = @($polId)
    scopes = @(@($scopes | ForEach-Object { $_.id }))
    resources = @(@($resources | ForEach-Object { $_._id }))
  } | ConvertTo-Json -Depth 6
  Invoke-RestMethod -Method Put -Uri "https://auth.asrax.in/admin/realms/$realm/clients/$rmId/authz/resource-server/permission/scope/$impersonatePermId" `
    -Headers $h -Body $body | Out-Null
  Write-Host "impersonation OK $realm (policy $polId)"
}

$configs = [ordered]@{
  "am-dev-realm" = @{
    ui        = "https://am-dev.asrax.in"
    redirects = @(
      "https://am-dev.asrax.in/*", "http://localhost:9000/*", "http://127.0.0.1:9000/*",
      "http://localhost:9000/callback", "http://127.0.0.1:9000/callback",
      "http://localhost:9000/oauth_callback.html", "http://127.0.0.1:9000/oauth_callback.html"
    )
  }
  "am-preprod-realm" = @{
    ui        = "https://am-preprod.asrax.in"
    redirects = @("https://am-preprod.asrax.in/*", "http://localhost:9000/*", "http://127.0.0.1:9000/*")
  }
}

$out = [ordered]@{}
foreach ($realm in $configs.Keys) {
  Write-Host "==== $realm ===="
  Ensure-Realm $realm
  foreach ($role in @("am-admin", "am-ops", "am-viewer", "am-user")) { Ensure-Role $realm $role }
  $idSec = Ensure-Client $realm "am-identity-service" (New-Secret) $configs[$realm].redirects
  $mcpSec = Ensure-Client $realm "am-mcp-service" (New-Secret) $configs[$realm].redirects
  Ensure-User $realm $DemoEmail $DemoPassword
  Ensure-IdentityImpersonation $realm
  $out[$realm] = @{
    KEYCLOAK_URL              = "https://auth.asrax.in"
    KEYCLOAK_REALM            = $realm
    OIDC_ISSUER               = "https://auth.asrax.in/realms/$realm"
    OIDC_DISCOVERY_URL        = "https://auth.asrax.in/realms/$realm/.well-known/openid-configuration"
    OIDC_JWKS_URL             = "https://auth.asrax.in/realms/$realm/protocol/openid-connect/certs"
    OIDC_TOKEN_URL            = "https://auth.asrax.in/realms/$realm/protocol/openid-connect/token"
    AM_IDENTITY_CLIENT_ID     = "am-identity-service"
    AM_IDENTITY_CLIENT_SECRET = $idSec
    AM_MCP_CLIENT_ID          = "am-mcp-service"
    AM_MCP_CLIENT_SECRET      = $mcpSec
    AUTH_UI_BASE_URL          = $configs[$realm].ui
    KEYCLOAK_ADMIN_USER       = "admin"
    KEYCLOAK_ADMIN_PASSWORD   = $AdminPassword
  }
  Write-Host "ok $realm"
}

$tokBody = @{
  grant_type = "password"; client_id = "am-identity-service"
  client_secret = $out["am-dev-realm"].AM_IDENTITY_CLIENT_SECRET
  username = $DemoEmail; password = $DemoPassword
}
$t = Invoke-RestMethod -Method Post -Uri "https://auth.asrax.in/realms/am-dev-realm/protocol/openid-connect/token" `
  -Headers @{ "User-Agent" = $ua } -Body $tokBody -ContentType "application/x-www-form-urlencoded"
Write-Host "dig password-grant OK len=$($t.access_token.Length)"

$out | ConvertTo-Json -Depth 6 | Set-Content -Path $OutFile -Encoding utf8
Write-Host "wrote $OutFile"
