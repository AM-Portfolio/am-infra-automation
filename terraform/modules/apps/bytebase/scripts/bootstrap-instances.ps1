# Register Contabo PG + Mongo + Redis instances under Dev/Preprod/Prod in Bytebase.
# Prereq: bootstrap-workspace.ps1; port-forward optional (uses PF to svc/bytebase :18080).
# Free plan: activation=false (activation:true hits Community activation limit).

param(
  [string] $Kubeconfig = "$env:USERPROFILE\.asrax\kubeconfig.prod",
  [string] $CredFile = "$env:USERPROFILE\.asrax\credentials.d\bytebase-ccot.env",
  [string] $BytebaseUrl = "http://127.0.0.1:18080",
  [string] $Namespace = "infra"
)

$ErrorActionPreference = "Stop"
$env:KUBECONFIG = $Kubeconfig

if (-not (Test-Path $CredFile)) { throw "Missing $CredFile — run bootstrap-workspace.ps1 first" }
$vars = @{}
Get-Content $CredFile | ForEach-Object {
  if ($_ -match '^\s*([A-Z0-9_]+)=(.*)$') { $vars[$Matches[1]] = $Matches[2].Trim().Trim('"') }
}

# Ensure local port-forward
$pf = $null
try {
  Invoke-WebRequest "$BytebaseUrl/" -UseBasicParsing -TimeoutSec 3 | Out-Null
} catch {
  $pf = Start-Process -FilePath kubectl -ArgumentList @('--kubeconfig', $Kubeconfig, '-n', $Namespace, 'port-forward', 'svc/bytebase', '18080:80') -PassThru -WindowStyle Hidden
  Start-Sleep 5
}

function Get-B64([string]$secret, [string]$key) {
  $raw = kubectl -n $Namespace get secret $secret -o jsonpath="{.data.$key}"
  return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($raw))
}

$login = Invoke-RestMethod -Uri "$BytebaseUrl/v1/auth/login" -Method POST -ContentType 'application/json' -Body (@{
  email = $vars['BYTEBASE_ADMIN_EMAIL']; password = $vars['BYTEBASE_ADMIN_PASSWORD']
} | ConvertTo-Json)
$h = @{ Authorization = "Bearer $($login.token)"; 'Content-Type' = 'application/json' }

$pgUser = Get-B64 'postgresql-secret' 'POSTGRES_USER'
$pgPass = Get-B64 'postgresql-secret' 'POSTGRES_PASSWORD'
$mongoPass = Get-B64 'mongodb' 'mongodb-root-password'
$redisConf = kubectl -n $Namespace get cm redis-config -o jsonpath='{.data.redis\.conf}'
$redisPass = ($redisConf | Select-String -Pattern 'requirepass\s+(\S+)').Matches.Groups[1].Value

$existing = @{}
try {
  (Invoke-RestMethod -Uri "$BytebaseUrl/v1/instances" -Headers $h).instances | ForEach-Object {
    $existing[($_.name -split '/')[-1]] = $_
  }
} catch { }

foreach ($envName in @('dev', 'preprod', 'prod')) {
  $label = if ($envName -eq 'preprod') { 'Preprod' } else { $envName.Substring(0, 1).ToUpper() + $envName.Substring(1) }
  $specs = @(
    @{ id = "pg-$envName"; title = "Postgres $label"; engine = 'POSTGRES'; host = 'postgresql'; port = '5432'; user = $pgUser; pass = $pgPass },
    @{ id = "mongo-$envName"; title = "Mongo $label"; engine = 'MONGODB'; host = 'mongodb'; port = '27017'; user = 'admin'; pass = $mongoPass; database = 'admin' },
    @{ id = "redis-$envName"; title = "Redis $label"; engine = 'REDIS'; host = 'redis-master'; port = '6379'; user = ''; pass = $redisPass }
  )
  foreach ($s in $specs) {
    $ds = @{
      id = 'admin'; type = 'ADMIN'; username = $s.user; password = $s.pass; host = $s.host; port = $s.port
    }
    if ($s.ContainsKey('database')) { $ds.database = $s.database }
    $body = @{
      title = $s.title; engine = $s.engine; activation = $false
      environment = "environments/$envName"; dataSources = @($ds)
    } | ConvertTo-Json -Depth 6

    if ($existing.ContainsKey($s.id)) {
      Write-Host "exists $($s.id) — patching dataSources"
      try {
        Invoke-RestMethod -Uri "$BytebaseUrl/v1/instances/$($s.id)?update_mask=data_sources" -Method PATCH -Headers $h -Body (@{ dataSources = @($ds) } | ConvertTo-Json -Depth 6) | Out-Null
      } catch { Write-Warning "patch $($s.id): $_" }
    } else {
      try {
        Invoke-RestMethod -Uri "$BytebaseUrl/v1/instances?instanceId=$($s.id)" -Method POST -Headers $h -Body $body | Out-Null
        Write-Host "created $($s.id)"
      } catch { Write-Warning "create $($s.id): $_" }
    }
    try {
      Invoke-RestMethod -Uri "$BytebaseUrl/v1/instances/$($s.id):sync" -Method POST -Headers $h -Body '{}' | Out-Null
      Write-Host "synced $($s.id)"
    } catch { Write-Warning "sync $($s.id): $_" }
  }
}

if ($pf) { Stop-Process -Id $pf.Id -Force -ErrorAction SilentlyContinue }
Write-Host "Done. Open https://bytebase.asrax.in — Environments Dev/Preprod/Prod × pg/mongo/redis."
