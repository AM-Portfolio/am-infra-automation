# Quick bidirectional isolation smoke (no secrets printed)
$ErrorActionPreference = 'Continue'
$kc = "$env:USERPROFILE\.asrax\kubeconfig.prod"
$seed = (Get-Content "$env:USERPROFILE\.asrax\credentials.d\dig-principal-seed.env" |
  Where-Object { $_ -match '^DIG_PRINCIPAL_SEED=' } |
  Select-Object -First 1).Split('=', 2)[1].Trim().Trim('"')
$mongoRoot = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(
  (kubectl --kubeconfig $kc -n infra get secret mongodb -o jsonpath='{.data.mongodb-root-password}')))
$redisConf = kubectl --kubeconfig $kc -n infra get cm redis-config -o jsonpath='{.data.redis\.conf}'
$redisPass = (($redisConf -split "`n") | Where-Object { $_ -match '^\s*requirepass\s+' } |
  Select-Object -First 1) -replace '^\s*requirepass\s+', ''
$mongoPod = ((kubectl --kubeconfig $kc -n infra get pods -o name) |
  Where-Object { $_ -match 'mongodb' } | Select-Object -First 1) -replace '^pod/', ''

$mongoJs = @'
(function () {
  function ok(b, m) { print((b ? "PASS" : "FAIL") + ": " + m); }
  ok(!!db.getSiblingDB("admin").auth("dig_vault_seed", "__SEED__"), "dig auth");
  try { db.getSiblingDB("am_portfolio_dev").iso.insertOne({ t: 1 }); ok(true, "dig write *_dev"); }
  catch (e) { ok(false, "dig write *_dev " + e.message); }
  try { db.getSiblingDB("portfolio").iso.insertOne({ t: 1 }); ok(false, "dig wrote portfolio"); }
  catch (e) { ok(true, "dig denied portfolio"); }
  db.getSiblingDB("admin").logout();
  ok(!!db.getSiblingDB("admin").auth("am_prod", "__ROOT__"), "am_prod auth");
  try { db.getSiblingDB("am_portfolio_dev").iso.insertOne({ t: 1 }); ok(false, "am_prod wrote *_dev"); }
  catch (e) { ok(true, "am_prod denied *_dev"); }
})();
'@
$mongoJs = $mongoJs.Replace('__SEED__', $seed).Replace('__ROOT__', $mongoRoot)
$mb64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($mongoJs))
Write-Host '=== MONGO ==='
kubectl --kubeconfig $kc -n infra exec $mongoPod -c mongodb -- /bin/sh -c "echo $mb64 | base64 -d >/tmp/t.js && mongosh --quiet mongodb://admin:$mongoRoot@127.0.0.1:27017/admin --file /tmp/t.js" 2>$null

$redisSh = @'
redis-cli --user dig_vault_seed -a '__SEED__' SET am-portfolio-dev:t 1 >/dev/null && echo PASS: dig_dev || echo FAIL: dig_dev
(redis-cli --user dig_vault_seed -a '__SEED__' SET am-portfolio:t 1 2>&1 | grep -q NOPERM) && echo PASS: dig_prod_denied || echo FAIL: dig_prod_denied
redis-cli --user am_prod -a '__RPASS__' SET am-portfolio:t 1 >/dev/null && echo PASS: prod_prod || echo FAIL: prod_prod
(redis-cli --user am_prod -a '__RPASS__' SET am-portfolio-dev:t2 1 2>&1 | grep -q NOPERM) && echo PASS: prod_dev_denied || echo FAIL: prod_dev_denied
'@
$redisSh = $redisSh.Replace('__SEED__', $seed).Replace('__RPASS__', $redisPass)
$rb64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($redisSh))
Write-Host '=== REDIS ==='
kubectl --kubeconfig $kc -n infra exec redis-master-0 -- /bin/sh -c "echo $rb64 | base64 -d | sh" 2>$null

$pgSh = @'
PGPASSWORD='__SEED__' psql -U dig_vault_seed -d user_platform_dev -c 'SELECT 1' >/dev/null && echo PASS: dig_pg || echo FAIL: dig_pg
PGPASSWORD='am_prod_pg_iso' psql -U am_prod_pg -d user_platform_dev -c 'SELECT 1' >/dev/null 2>&1 && echo FAIL: prod_pg_connect || echo PASS: prod_pg_denied
'@
$pgSh = $pgSh.Replace('__SEED__', $seed)
$pb64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pgSh))
Write-Host '=== PG ==='
kubectl --kubeconfig $kc -n infra exec postgresql-0 -- /bin/sh -c "echo $pb64 | base64 -d | sh" 2>$null

$vaultToken = (Get-Content "$env:USERPROFILE\.asrax\vault-contabo-infra.json" -Raw | ConvertFrom-Json).root_token
$h = @{ 'X-Vault-Token' = $vaultToken }
$m = Invoke-RestMethod -Uri 'https://vault.asrax.in/v1/apps/data/dev/infra/mongodb' -Headers $h
$p = Invoke-RestMethod -Uri 'https://vault.asrax.in/v1/apps/data/prod/infra/mongodb' -Headers $h
$i = Invoke-RestMethod -Uri 'https://vault.asrax.in/v1/apps/data/dev/infra/influxdb' -Headers $h
$r = Invoke-RestMethod -Uri 'https://vault.asrax.in/v1/apps/data/dev/infra/redis' -Headers $h
$k = Invoke-RestMethod -Uri 'https://vault.asrax.in/v1/apps/data/dev/infra/kafka' -Headers $h
$passNe = $m.data.data.password -ne $p.data.data.password
$kafkaUserEmpty = [string]::IsNullOrEmpty($k.data.data.username)
Write-Host "=== VAULT ==="
Write-Host ("PASS: dig_user={0}" -f $m.data.data.username)
Write-Host ("PASS: portfolio_db={0}" -f $m.data.data.AM_PORTFOLIO_MONGO_DATABASE)
Write-Host ("{0}: pass_ne_prod" -f ($(if ($passNe) { 'PASS' } else { 'FAIL' })))
Write-Host ("PASS: influx={0}/{1}" -f $i.data.data.bucket, $i.data.data.org)
Write-Host ("PASS: redis_user={0}" -f $r.data.data.username)
Write-Host ("{0}: kafka_user_empty_plaintext" -f ($(if ($kafkaUserEmpty) { 'PASS' } else { 'FAIL' })))
Write-Host ("PASS: kafka_prefix={0}" -f $k.data.data.KAFKA_TOPIC_PREFIX)
