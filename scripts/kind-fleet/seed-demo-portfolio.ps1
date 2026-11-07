# Copy Contabo prod demo portfolio into dig (am_portfolio_dev) and preprod (portfolio_preprod).
# Live Contabo prod DEMO_PORTFOLIO_ID = f969745c-f492-4b86-88ed-6588e9f28bb3 (Vault apps/data/prod/services/am-portfolio).
# Requires: ~/.asrax/kubeconfig.prod → Contabo infra Mongo.
param(
  [string] $Kubeconfig = "$env:USERPROFILE\.asrax\kubeconfig.prod",
  [string] $Namespace = "infra",
  [string] $DemoId = "f969745c-f492-4b86-88ed-6588e9f28bb3",
  [string] $SourceDb = "portfolio",
  [string[]] $TargetDbs = @("am_portfolio_dev", "portfolio_preprod")
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Kubeconfig)) { throw "Missing $Kubeconfig" }

$mongoPod = kubectl --kubeconfig $Kubeconfig -n $Namespace get pod -l app.kubernetes.io/name=mongodb -o jsonpath='{.items[0].metadata.name}' 2>$null
if (-not $mongoPod) {
  $mongoPod = (kubectl --kubeconfig $Kubeconfig -n $Namespace get pods -o name | Select-String 'mongodb' | Select-Object -First 1)
  if ($mongoPod) { $mongoPod = $mongoPod.ToString().Replace('pod/', '') }
}
if (-not $mongoPod) { throw "mongodb pod not found in $Namespace" }

$rootB64 = kubectl --kubeconfig $Kubeconfig -n $Namespace get secret mongodb -o jsonpath='{.data.mongodb-root-password}'
$rootPass = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($rootB64))
$targetsJson = ($TargetDbs | ForEach-Object { "'$_'" }) -join ', '

$js = @"
const demoId = '$DemoId';
const src = db.getSiblingDB('$SourceDb').portfolios.findOne({_id: demoId});
if (!src) { throw new Error('source missing: $SourceDb.portfolios ' + demoId); }
const targets = [$targetsJson];
for (const t of targets) {
  const d = db.getSiblingDB(t);
  const r = d.portfolios.replaceOne({_id: demoId}, src, {upsert: true});
  const check = d.portfolios.findOne({_id: demoId});
  const eq = (check.equities || check.equityModels || []).length;
  print(t + ' matched=' + r.matchedCount + ' modified=' + r.modifiedCount + ' upserted=' + (r.upsertedCount || 0) + ' equities=' + eq + ' name=' + check.name + ' owner=' + check.owner);
}
print('seed-demo-portfolio OK id=' + demoId);
"@

$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($js))
Write-Host "mongoPod=$mongoPod demoId=$DemoId source=$SourceDb targets=$($TargetDbs -join ',')"
kubectl --kubeconfig $Kubeconfig -n $Namespace exec $mongoPod -c mongodb -- /bin/sh -c `
  "echo $b64 | base64 -d > /tmp/seed-demo-portfolio.js && mongosh --quiet 'mongodb://admin:$rootPass@127.0.0.1:27017/admin' --file /tmp/seed-demo-portfolio.js"
if ($LASTEXITCODE -ne 0) { throw "mongosh seed failed" }
