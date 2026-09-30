# IAM Contabo env=dev: shared dig_vault_seed + *_dev resources on Contabo infra.
# One shared env=dev login per engine; catalog lists resource inventory (*_dev DBs/prefixes).
# Seed: ~/.asrax/credentials.d/dig-principal-seed.env (DIG_PRINCIPAL_SEED)
# Catalog: ../catalog/dig-contabo-users.yaml

param(
  [string] $Kubeconfig = "$env:USERPROFILE\.asrax\kubeconfig.prod",
  [string] $Catalog = (Join-Path $PSScriptRoot "..\catalog\dig-contabo-users.yaml"),
  [string] $Namespace = "infra"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Kubeconfig)) { throw "Missing $Kubeconfig" }
if (-not (Test-Path $Catalog)) { throw "Missing $Catalog" }

$seedFile = Join-Path $env:USERPROFILE ".asrax\credentials.d\dig-principal-seed.env"
$Seed = $env:DIG_PRINCIPAL_SEED
if ([string]::IsNullOrWhiteSpace($Seed) -and (Test-Path $seedFile)) {
  $line = Get-Content $seedFile | Where-Object { $_ -match '^\s*DIG_PRINCIPAL_SEED=' } | Select-Object -First 1
  if ($line) { $Seed = ($line -split '=', 2)[1].Trim().Trim('"') }
}
if ([string]::IsNullOrWhiteSpace($Seed) -or $Seed.Length -lt 16) {
  $bytes = New-Object byte[] 24
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $Seed = (([Convert]::ToBase64String($bytes) -replace '[^a-zA-Z0-9]', 'x').Substring(0, 24))
  New-Item -ItemType Directory -Force -Path (Split-Path $seedFile) | Out-Null
  Set-Content $seedFile "DIG_PRINCIPAL_SEED=$Seed" -Encoding ascii
  Write-Host "Wrote $seedFile"
}

function Get-Pw([string]$engine, [string]$logical) {
  $prefix = switch ($engine) { "postgresql" { "pg" } "mongodb" { "mongo" } "redis" { "redis" } "minio" { "minio" } "kafka" { "kafka" } default { $engine } }
  $msg = "$prefix|$logical|dev|$Seed"
  $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($msg))
  return ((-join ($hash | ForEach-Object { $_.ToString('x2') })).Substring(0, 32))
}

function Get-Users([string]$section) {
  $list = New-Object System.Collections.Generic.List[hashtable]
  $in = $false
  $cur = $null
  foreach ($line in [IO.File]::ReadAllLines($Catalog)) {
    $t = $line.TrimEnd("`r")
    if ($t -match "^${section}:\s*$") { $in = $true; continue }
    if ($in -and $t -match '^[a-zA-Z].*:') {
      if ($null -ne $cur) { $list.Add($cur); $cur = $null }
      break
    }
    if (-not $in) { continue }
    if ($t -match '^\s*-\s+name:\s*(\S+)') {
      if ($null -ne $cur) { $list.Add($cur) }
      $cur = @{ name = $Matches[1]; logical = ''; database = ''; role = 'readWrite'; key_prefix = ''; topic_prefix = ''; prefix = ''; createdb = $false }
      continue
    }
    if ($null -eq $cur) { continue }
    if ($t -match '^\s+logical:\s*"?([^"]+)"?\s*$') { $cur.logical = $Matches[1].Trim() }
    if ($t -match '^\s+database:\s*(\S+)') { $cur.database = $Matches[1] }
    if ($t -match '^\s+role:\s*(\S+)') { $cur.role = $Matches[1] }
    if ($t -match '^\s+key_prefix:\s*"([^"]+)"') { $cur.key_prefix = $Matches[1] }
    elseif ($t -match '^\s+key_prefix:\s*(\S+)') { $cur.key_prefix = $Matches[1] }
    if ($t -match '^\s+topic_prefix:\s*(\S+)') { $cur.topic_prefix = $Matches[1] }
    if ($t -match '^\s+prefix:\s*(\S+)') { $cur.prefix = ($Matches[1].TrimEnd('/') + '/') }
    if ($t -match '^\s+createdb:\s*true') { $cur.createdb = $true }
  }
  if ($null -ne $cur) { $list.Add($cur) }
  return $list
}

$pg = Get-Users 'postgresql'
$mongo = Get-Users 'mongodb'
$redis = Get-Users 'redis'
$minio = Get-Users 'minio'
$kafka = Get-Users 'kafka'
Write-Host ("Catalog: pg={0} mongo={1} redis={2} minio={3} kafka={4}" -f $pg.Count, $mongo.Count, $redis.Count, $minio.Count, $kafka.Count)

$ErrorActionPreference = "Continue"
$mongoPod = (& kubectl --kubeconfig $Kubeconfig -n $Namespace get pod -l app.kubernetes.io/name=mongodb -o jsonpath='{.items[0].metadata.name}' 2>$null)
if (-not $mongoPod) {
  $mongoPod = (& kubectl --kubeconfig $Kubeconfig -n $Namespace get pod -l app=mongodb -o jsonpath='{.items[0].metadata.name}' 2>$null)
}
if (-not $mongoPod) {
  $mongoPod = (& kubectl --kubeconfig $Kubeconfig -n $Namespace get pods -o name 2>$null | Where-Object { $_ -match 'mongodb' } | Select-Object -First 1)
  if ($mongoPod) { $mongoPod = $mongoPod -replace '^pod/','' }
}
if (-not $mongoPod) { throw "mongodb pod not found" }
$pgPod = 'postgresql-0'
$redisPod = 'redis-master-0'
$minioPod = (& kubectl --kubeconfig $Kubeconfig -n $Namespace get pod -l app.kubernetes.io/name=minio -o jsonpath='{.items[0].metadata.name}' 2>$null)
if (-not $minioPod) { $minioPod = 'minio-0' }
$ErrorActionPreference = "Stop"

$mongoRoot = (& kubectl --kubeconfig $Kubeconfig -n $Namespace get secret mongodb -o jsonpath='{.data.mongodb-root-password}' | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) })
$pgUser = (& kubectl --kubeconfig $Kubeconfig -n $Namespace get secret postgresql-secret -o jsonpath='{.data.POSTGRES_USER}' | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) })
$pgPass = (& kubectl --kubeconfig $Kubeconfig -n $Namespace get secret postgresql-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) })
$redisConf = (& kubectl --kubeconfig $Kubeconfig -n $Namespace get cm redis-config -o jsonpath='{.data.redis\.conf}')
$redisPass = (($redisConf -split "`n") | Where-Object { $_ -match '^\s*requirepass\s+' } | Select-Object -First 1) -replace '^\s*requirepass\s+',''
$minioUser = (& kubectl --kubeconfig $Kubeconfig -n $Namespace get secret minio-secret -o jsonpath='{.data.MINIO_ROOT_USER}' | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) })
$minioPass = (& kubectl --kubeconfig $Kubeconfig -n $Namespace get secret minio-secret -o jsonpath='{.data.MINIO_ROOT_PASSWORD}' | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) })

function Invoke-MongoEval([string]$js) {
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($js))
  $cmd = "echo $b64 | base64 -d > /tmp/iam.js && mongosh --quiet mongodb://admin:$mongoRoot@127.0.0.1:27017/admin --file /tmp/iam.js"
  & kubectl --kubeconfig $Kubeconfig -n $Namespace exec $mongoPod -c mongodb -- /bin/sh -c $cmd
  if ($LASTEXITCODE -ne 0) { throw "mongo eval failed" }
}

# --- Mongo: shared dig_vault_seed RW only on *_dev DBs; optional inventory users ---
$mongoDbs = @($mongo | ForEach-Object { $_.database } | Where-Object { $_ } | Select-Object -Unique)
$roleParts = ($mongoDbs | ForEach-Object { "{ role: 'readWrite', db: '$_' }" }) -join ', '
$ensureDbParts = ($mongoDbs | ForEach-Object { "db.getSiblingDB('$_').createCollection('_iam_keep');" }) -join "`n  "
Write-Host "Mongo dig_vault_seed roles on $($mongoDbs.Count) *_dev DBs via $mongoPod"
# am_prod password = Contabo mongo root (same as current prod app admin login) — not DIG seed
$seedJs = @"
(function () {
  var roles = [ $roleParts ];
  try { db.getSiblingDB('admin').createUser({ user: 'dig_vault_seed', pwd: '$Seed', roles: roles }); }
  catch (e) {
    if (/already exists/.test(e.message)) { db.getSiblingDB('admin').updateUser('dig_vault_seed', { pwd: '$Seed', roles: roles }); }
    else { throw e; }
  }
  $ensureDbParts
  // Prod app login (non-root): RW only known prod DBs — bidirectional isolation
  var prodDbs = [
    'am_oms','am_notification','am_news','am_portfolio','am_trade','am_analysis','am_logging',
    'am_asrax_corp','am_mkt','am_mkt_agents','am_engage','am_mcp','am_db_agent','am_tool_agent',
    'am_qa_agent','am_fin_agent','am_doc_intel','am_docs','am_analytics','portfolio','trade',
    'analysis','mcp','market_data','mutual_funds','am_ui_testing','fin_agent','am_support_agent'
  ];
  var prodRoles = prodDbs.map(function (d) { return { role: 'readWrite', db: d }; });
  try { db.getSiblingDB('admin').createUser({ user: 'am_prod', pwd: '$mongoRoot', roles: prodRoles }); }
  catch (e) {
    if (/already exists/.test(e.message)) { db.getSiblingDB('admin').updateUser('am_prod', { pwd: '$mongoRoot', roles: prodRoles }); }
    else { throw e; }
  }
  print('mongo dig_vault_seed + am_prod ok');
})();
"@
Invoke-MongoEval $seedJs
foreach ($u in $mongo) {
  $pw = Get-Pw 'mongodb' $u.logical
  $js = @"
try { db.getSiblingDB('admin').createUser({ user: '$($u.name)', pwd: '$pw', roles: [{ role: '$($u.role)', db: '$($u.database)' }] }) }
catch (e) { if (/already exists/.test(e.message)) { db.getSiblingDB('admin').updateUser('$($u.name)', { pwd: '$pw', roles: [{ role: '$($u.role)', db: '$($u.database)' }] }); } else { throw e; } }
"@
  Write-Host "  mongo inventory $($u.name) / $($u.database)"
  Invoke-MongoEval $js
}

# --- Postgres: dig_vault_seed owns *_dev DBs; REVOKE PUBLIC ---
Write-Host "Postgres dig_vault_seed + $($pg.Count) DBs via $pgPod"
$pgSql = @"
DO `$`$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='dig_vault_seed') THEN
    CREATE ROLE dig_vault_seed LOGIN PASSWORD '$Seed';
  ELSE
    ALTER ROLE dig_vault_seed PASSWORD '$Seed';
  END IF;
END `$`$;
"@
$pgSqlB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pgSql))
& kubectl --kubeconfig $Kubeconfig -n $Namespace exec $pgPod -- /bin/sh -c "echo $pgSqlB64 | base64 -d > /tmp/dig_pg.sql && PGPASSWORD='$pgPass' psql -U $pgUser -d postgres -f /tmp/dig_pg.sql"
foreach ($u in $pg) {
  $db = $u.database
  Write-Host "  pg dig DB $db"
  $ensureDb = @"
PGPASSWORD='$pgPass' psql -U $pgUser -d postgres -tc "SELECT 1 FROM pg_database WHERE datname='$db'" | grep -q 1 \
  || PGPASSWORD='$pgPass' psql -U $pgUser -d postgres -c "CREATE DATABASE $db OWNER dig_vault_seed"
PGPASSWORD='$pgPass' psql -U $pgUser -d postgres -c "ALTER DATABASE $db OWNER TO dig_vault_seed; REVOKE ALL ON DATABASE $db FROM PUBLIC; GRANT CONNECT ON DATABASE $db TO dig_vault_seed;"
PGPASSWORD='$pgPass' psql -U $pgUser -d $db -c "GRANT ALL ON SCHEMA public TO dig_vault_seed;" || true
"@
  $ensureB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($ensureDb))
  & kubectl --kubeconfig $Kubeconfig -n $Namespace exec $pgPod -- /bin/sh -c "echo $ensureB64 | base64 -d | sh"
  $pw = Get-Pw 'postgresql' $u.logical
  $roleSql = @"
DO `$`$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='$($u.name)') THEN
    CREATE ROLE $($u.name) LOGIN PASSWORD '$pw';
  ELSE
    ALTER ROLE $($u.name) PASSWORD '$pw';
  END IF;
END `$`$;
"@
  $roleB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($roleSql))
  & kubectl --kubeconfig $Kubeconfig -n $Namespace exec $pgPod -- /bin/sh -c "echo $roleB64 | base64 -d > /tmp/dig_role.sql && PGPASSWORD='$pgPass' psql -U $pgUser -d postgres -f /tmp/dig_role.sql"
  $grantInv = @"
PGPASSWORD='$pgPass' psql -U $pgUser -d $db -c "GRANT ALL ON SCHEMA public TO $($u.name);" || true
"@
  $grantB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($grantInv))
  & kubectl --kubeconfig $Kubeconfig -n $Namespace exec $pgPod -- /bin/sh -c "echo $grantB64 | base64 -d | sh"
}

# --- Redis: dig_vault_seed ACL only am-*-dev: prefixes; am_prod ACL for prod prefixes ---
Write-Host "Redis ACL dig_vault_seed (dev prefixes only) via $redisPod"
$devPats = @($redis | ForEach-Object { if ($_.key_prefix) { "~$($_.key_prefix)*" } } | Where-Object { $_ })
$devPatArgs = ($devPats -join ' ')
$ErrorActionPreference = "Continue"
& kubectl --kubeconfig $Kubeconfig -n $Namespace exec $redisPod -- /bin/sh -c "redis-cli -a '$redisPass' ACL DELUSER dig_vault_seed" 2>$null | Out-Null
# +info: Spring Boot Redis health uses INFO; INFO is in @dangerous so re-add explicitly.
$aclCmd = "ACL SETUSER dig_vault_seed on '>${Seed}' ${devPatArgs} +@all -@dangerous +info"
Write-Host "  ACL SETUSER dig_vault_seed on >*** ${devPatArgs} +@all -@dangerous +info"
$aclB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("redis-cli -a '$redisPass' $aclCmd"))
& kubectl --kubeconfig $Kubeconfig -n $Namespace exec $redisPod -- /bin/sh -c "echo $aclB64 | base64 -d | sh"
foreach ($u in $redis) {
  $pw = Get-Pw 'redis' $u.logical
  $pat = if ($u.key_prefix) { "~$($u.key_prefix)*" } else { '~*' }
  Write-Host "  redis inventory $($u.name) $pat"
  $invAcl = "redis-cli -a '$redisPass' ACL SETUSER $($u.name) on '>${pw}' ${pat} +@all -@dangerous"
  $invB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($invAcl))
  & kubectl --kubeconfig $Kubeconfig -n $Namespace exec $redisPod -- /bin/sh -c "echo $invB64 | base64 -d | sh" | Out-Null
}
& kubectl --kubeconfig $Kubeconfig -n $Namespace exec $redisPod -- /bin/sh -c "redis-cli -a '$redisPass' ACL DELUSER am_prod" 2>$null | Out-Null
$prodAcl = "redis-cli -a '$redisPass' ACL SETUSER am_prod on '>${redisPass}' ~am-market-data:* ~am-gateway:* ~am-portfolio:* ~am-trade:* ~am-analysis:* ~am-oms:* ~am-notification:* ~am-api-gateway:* +@all -@dangerous"
$prodAclB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($prodAcl))
& kubectl --kubeconfig $Kubeconfig -n $Namespace exec $redisPod -- /bin/sh -c "echo $prodAclB64 | base64 -d | sh" | Out-Null
$ErrorActionPreference = "Stop"

Write-Host "MinIO users ($($minio.Count)) via $minioPod (skipped if mc absent; MinIO out of isolation scope)"
$ErrorActionPreference = "Continue"
$mcCheck = (& kubectl --kubeconfig $Kubeconfig -n $Namespace exec $minioPod -- /bin/sh -c 'command -v mc >/dev/null 2>&1 && echo HAS_MC || echo NO_MC' 2>$null | Out-String).Trim()
if ($mcCheck -match 'HAS_MC') {
  $minioCmd = @"
mc alias set local http://127.0.0.1:9000 '$minioUser' '$minioPass' && mc mb --ignore-existing local/platform && mc admin user add local dig_vault_seed '$Seed' || true
"@
  $minioB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($minioCmd))
  & kubectl --kubeconfig $Kubeconfig -n $Namespace exec $minioPod -- /bin/sh -c "echo $minioB64 | base64 -d | sh"
  foreach ($u in $minio) {
    $pw = Get-Pw 'minio' $u.logical
    Write-Host "  minio $($u.name)"
    $mc = @"
mc admin user add local $($u.name) '$pw' || true
mc admin policy attach local readwrite --user $($u.name) || true
"@
    $mcB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($mc))
    & kubectl --kubeconfig $Kubeconfig -n $Namespace exec $minioPod -- /bin/sh -c "echo $mcB64 | base64 -d | sh"
  }
} else {
  Write-Host "  MinIO: mc not in pod - inventory only (out of scope)"
}
$ErrorActionPreference = "Stop"

Write-Host "Kafka: $($kafka.Count) topic prefixes (SCRAM when SASL enabled) - inventory only"

$pgNames = ($pg | ForEach-Object { $_.name } | Sort-Object) -join ','
$mongoNames = ($mongo | ForEach-Object { $_.name } | Sort-Object) -join ','
$redisNames = ($redis | ForEach-Object { $_.name } | Sort-Object) -join ','
$kafkaNames = ($kafka | ForEach-Object { $_.name } | Sort-Object) -join ','
$minioNames = ($minio | ForEach-Object { $_.name } | Sort-Object) -join ','
$mongoDbList = ($mongoDbs | Sort-Object) -join ','

$invLines = @(
  'apiVersion: v1'
  'kind: ConfigMap'
  'metadata:'
  '  name: db-users-inventory'
  "  namespace: $Namespace"
  '  labels:'
  '    app.kubernetes.io/part-of: am-access-plane'
  'data:'
  ('  postgresql_count: "{0}"' -f $pg.Count)
  ('  mongodb_count: "{0}"' -f $mongo.Count)
  ('  redis_count: "{0}"' -f $redis.Count)
  ('  kafka_count: "{0}"' -f $kafka.Count)
  ('  minio_count: "{0}"' -f $minio.Count)
  ('  postgresql_users: "{0}"' -f $pgNames)
  ('  mongodb_users: "{0}"' -f $mongoNames)
  ('  redis_users: "{0}"' -f $redisNames)
  ('  kafka_users: "{0}"' -f $kafkaNames)
  ('  minio_users: "{0}"' -f $minioNames)
  ('  mongodb_dev_dbs: "{0}"' -f $mongoDbList)
  '  catalog_note: "env=dev shared dig_vault_seed; star_dev resources; am_prod for prod-scoped app login; kafka SCRAM deferred if PLAINTEXT"'
  '  dig_vault_seed_user: "dig_vault_seed"'
  '  prod_app_user: "am_prod"'
)
$invFile = Join-Path $env:TEMP 'db-users-inventory.yaml'
[IO.File]::WriteAllLines($invFile, $invLines)
& kubectl --kubeconfig $Kubeconfig apply -f $invFile
Write-Host "DONE - inventory applied. Seed: $seedFile"
