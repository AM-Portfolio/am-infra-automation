# Laptop: co_locate_on_infra=true for kind-fleet/dev/platform
$ErrorActionPreference = "Stop"
# Terraform local-exec uses interpreter=["bash","-c"]; Git bash must be on PATH
$gitRoot = "C:\Program Files\Git"
if (Test-Path "$gitRoot\bin\bash.exe") {
  $env:PATH = "$gitRoot\bin;$gitRoot\usr\bin;" + $env:PATH
}
$Plat = "f:\am-repos\am-repos\am-infra-automation\terraform\kind-fleet\dev\platform"
$StateDir = Join-Path $env:USERPROFILE ".asrax\tfstate\dev\platform"
$StoresEnv = Join-Path $env:USERPROFILE ".asrax\credentials.d\dev-infra-stores.env"
$KcInfra = Join-Path $env:USERPROFILE ".asrax\kubeconfig.am-dev-infra.yaml"
$KcPlat = Join-Path $env:USERPROFILE ".asrax\kubeconfig.am-dev-platform.yaml"

function Get-EnvFileValue([string]$path, [string]$key) {
  $line = Get-Content $path | Where-Object { $_ -match "^$key=(.*)$" } | Select-Object -First 1
  if (-not $line) { return "" }
  return ($line -split "=", 2)[1].Trim()
}

function Get-StoresAppPassword([string]$user) {
  $py = @"
import json
st=json.load(open(r'$env:USERPROFILE\.asrax\tfstate\dev\stores\terraform.tfstate',encoding='utf-8'))
for r in st.get('resources',[]):
  if r.get('type')=='random_password' and r.get('name')=='app_users':
    for inst in r.get('instances',[]):
      if inst.get('index_key')=='$user':
        print(inst['attributes']['result'], end='')
        raise SystemExit
"@
  return (python -c $py)
}

# Build passwords from stores.env + TF state + live keycloak secret
$kcPass = ""
if (Test-Path $KcPlat) {
  $b64 = kubectl --kubeconfig $KcPlat -n identity get secret keycloak-db -o jsonpath="{.data.password}" 2>$null
  if ($b64) { $kcPass = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) }
}
if (-not $kcPass) { $kcPass = Get-EnvFileValue $StoresEnv "PG_USER_KEYCLOAK" }
if (-not $kcPass) { $kcPass = Get-StoresAppPassword "keycloak" }

$n8nPass = Get-EnvFileValue $StoresEnv "PG_USER_N8N"
if (-not $n8nPass) { $n8nPass = Get-StoresAppPassword "n8n" }

$tfvars = @"
co_locate_on_infra = true
keycloak_db_password = "$kcPass"
temporal_db_password = "$(Get-EnvFileValue $StoresEnv 'PG_USER_TEMPORAL')"
lago_db_password = "$(Get-EnvFileValue $StoresEnv 'PG_USER_LAGO')"
n8n_db_password = "$n8nPass"
openproject_db_password = "$(Get-EnvFileValue $StoresEnv 'PG_USER_OPENPROJECT')"
litellm_db_password = "$(Get-EnvFileValue $StoresEnv 'PG_USER_LITELLM')"
langfuse_db_password = "$(Get-EnvFileValue $StoresEnv 'PG_USER_LANGFUSE')"
growthbook_mongo_password = "$(Get-EnvFileValue $StoresEnv 'MONGO_USER_GROWTHBOOK')"
langfuse_minio_password = "$(Get-EnvFileValue $StoresEnv 'MINIO_USER_LANGFUSE')"
mongo_admin_password = "$(Get-EnvFileValue $StoresEnv 'MONGO_PASSWORD')"
redis_password = "$(Get-EnvFileValue $StoresEnv 'REDIS_PASSWORD')"
"@

$tfvarsPath = Join-Path $StateDir "colocate.auto.tfvars"
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
if (Test-Path $tfvarsPath) { Remove-Item $tfvarsPath -Force -ErrorAction SilentlyContinue }
# Prefer state-dir var-file (avoid writing secrets into the git WD)
[IO.File]::WriteAllText($tfvarsPath, ($tfvars -replace "`r`n", "`n"))
Write-Host "wrote tfvars (secrets redacted) path=$tfvarsPath"

# Ensure dedicated DB grants (subscription / user_platform) before platform moves
$pgPass = kubectl --kubeconfig $KcInfra -n infra get secret postgresql-secret -o jsonpath="{.data.POSTGRES_PASSWORD}"
$pgPass = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($pgPass))
$pgUser = kubectl --kubeconfig $KcInfra -n infra get secret postgresql-secret -o jsonpath="{.data.POSTGRES_USER}"
$pgUser = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($pgUser))

$sql = @'
DO $$ BEGIN CREATE ROLE am_subscription_user LOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE am_user_platform_user LOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
SELECT 'ok_roles';
'@
kubectl --kubeconfig $KcInfra -n infra exec -i postgresql-0 -c postgresql -- env "PGPASSWORD=$pgPass" psql -U $pgUser -d postgres -v ON_ERROR_STOP=1 -c $sql
foreach ($pair in @(@("am_subscription","am_subscription_user"), @("user_platform","am_user_platform_user"))) {
  $db = $pair[0]; $u = $pair[1]
  kubectl --kubeconfig $KcInfra -n infra exec -i postgresql-0 -c postgresql -- env "PGPASSWORD=$pgPass" psql -U $pgUser -d postgres -v ON_ERROR_STOP=0 -c "SELECT 1 FROM pg_database WHERE datname='$db'" | Out-Null
  $exists = kubectl --kubeconfig $KcInfra -n infra exec -i postgresql-0 -c postgresql -- env "PGPASSWORD=$pgPass" psql -U $pgUser -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname='$db'"
  if ($exists -ne "1") {
    kubectl --kubeconfig $KcInfra -n infra exec -i postgresql-0 -c postgresql -- env "PGPASSWORD=$pgPass" psql -U $pgUser -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE $db OWNER $u;"
    Write-Host "created database $db"
  }
  kubectl --kubeconfig $KcInfra -n infra exec -i postgresql-0 -c postgresql -- env "PGPASSWORD=$pgPass" psql -U $pgUser -d postgres -v ON_ERROR_STOP=0 -c "ALTER DATABASE $db OWNER TO $u;" | Out-Null
  kubectl --kubeconfig $KcInfra -n infra exec -i postgresql-0 -c postgresql -- env "PGPASSWORD=$pgPass" psql -U $pgUser -d $db -v ON_ERROR_STOP=1 -c "GRANT ALL ON SCHEMA public TO $u; GRANT ALL ON ALL TABLES IN SCHEMA public TO $u; GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO $u;"
  Write-Host "granted $db -> $u"
}

Push-Location $Plat
try {
  # Quote flags: PowerShell steals bare -input=...
  terraform.exe init "-backend-config=backend.hcl" "-input=false" "-reconfigure"
  if ($LASTEXITCODE -ne 0) { throw "init failed" }
  terraform.exe plan "-input=false" "-no-color" "-var-file=$tfvarsPath" "-out=$StateDir\colocate.tfplan" 2>&1 | Tee-Object -FilePath "$StateDir\colocate-plan.log"
  if ($LASTEXITCODE -ne 0) { throw "plan failed" }
  Select-String -Path "$StateDir\colocate-plan.log" -Pattern "Plan:|Error:" | Select-Object -First 20
  terraform.exe apply "-input=false" "-no-color" "$StateDir\colocate.tfplan" 2>&1 | Tee-Object -FilePath "$StateDir\colocate-apply.log"
  if ($LASTEXITCODE -ne 0) { throw "apply failed" }
} finally {
  Pop-Location
}

kind get clusters
kubectl --kubeconfig $KcInfra get ns | Select-Object -First 30
kubectl --kubeconfig $KcInfra -n identity get pods -o wide 2>$null
Write-Host "DEV_COLOCATE_DONE"
