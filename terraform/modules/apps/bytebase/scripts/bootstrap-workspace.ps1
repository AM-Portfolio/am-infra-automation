# Bootstrap Bytebase workspace admin CCOT and Environments (Dev/Preprod/Prod).
# Requires: kubectl → Contabo kubeconfig.prod; Bytebase Running in infra.
# Writes: ~/.asrax/credentials.d/bytebase-ccot.env (never commit).

param(
  [string] $Kubeconfig = "$env:USERPROFILE\.asrax\kubeconfig.prod",
  [string] $Namespace = "infra"
)

$ErrorActionPreference = "Stop"
$env:KUBECONFIG = $Kubeconfig

function New-Pass([int]$len = 28) {
  $bytes = New-Object byte[] $len
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  return (([Convert]::ToBase64String($bytes) -replace '[^a-zA-Z0-9]', 'A').Substring(0, $len))
}

$credDir = Join-Path $env:USERPROFILE ".asrax\credentials.d"
New-Item -ItemType Directory -Force -Path $credDir | Out-Null
$credFile = Join-Path $credDir "bytebase-ccot.env"

$adminPass = New-Pass
$ccotPass = New-Pass
$adminHash = python -c "import bcrypt,sys; print(bcrypt.hashpw(sys.argv[1].encode(), bcrypt.gensalt(rounds=10)).decode().replace('`$2b`$','`$2a`$',1))" $adminPass
$ccotHash = python -c "import bcrypt,sys; print(bcrypt.hashpw(sys.argv[1].encode(), bcrypt.gensalt(rounds=10)).decode().replace('`$2b`$','`$2a`$',1))" $ccotPass

$pgUrl = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((kubectl -n $Namespace get secret bytebase-pg -o jsonpath='{.data.PG_URL}')))
if ($pgUrl -notmatch 'postgresql://([^:]+):([^@]+)@') { throw "Cannot parse bytebase PG_URL" }
$bbUser = $Matches[1]; $bbPass = $Matches[2]

$envJson = '{"environments":[{"id":"dev","title":"Dev","color":{"red":0.2,"green":0.6,"blue":0.9}},{"id":"preprod","title":"Preprod","color":{"red":0.9,"green":0.6,"blue":0.2}},{"id":"prod","title":"Prod","color":{"red":0.31,"green":0.27,"blue":0.9}}]}'
$iamJson = '{"bindings":[{"role":"roles/workspaceAdmin","members":["users/admin@asrax.in","users/ccot@asrax.in"]},{"role":"roles/workspaceMember","members":["users/probe@asrax.in"]}]}'

$sql = @"
UPDATE principal SET password_hash = '$adminHash' WHERE email = 'admin@asrax.in';
INSERT INTO principal (name, email, password_hash)
VALUES ('CCOT', 'ccot@asrax.in', '$ccotHash')
ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash, name = EXCLUDED.name, deleted = false;
UPDATE setting SET value = '$($envJson.Replace("'","''"))'::jsonb WHERE name = 'ENVIRONMENT';
UPDATE policy SET payload = '$($iamJson.Replace("'","''"))'::jsonb, updated_at = now()
WHERE resource LIKE 'workspaces/%' AND type = 'IAM';
"@

$sql | kubectl -n $Namespace exec -i postgresql-0 -- env PGPASSWORD=$bbPass psql -U $bbUser -d bytebase | Out-Null

@"
BYTEBASE_URL=https://bytebase.asrax.in
BYTEBASE_ADMIN_EMAIL=admin@asrax.in
BYTEBASE_ADMIN_PASSWORD=$adminPass
BYTEBASE_CCOT_EMAIL=ccot@asrax.in
BYTEBASE_CCOT_PASSWORD=$ccotPass
"@ | Set-Content $credFile -Encoding ascii

Write-Host "Wrote $credFile (Environments Dev/Preprod/Prod + CCOT workspaceAdmin)."
