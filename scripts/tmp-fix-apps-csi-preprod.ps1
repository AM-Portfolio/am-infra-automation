# One-shot: remap am-apps-dev SPCs onto apps/data/preprod, refresh JWT JWKS, recreate pods.
$ErrorActionPreference = "Continue"
$KcA = Join-Path $env:USERPROFILE ".asrax\kubeconfig.am-dev-apps.yaml"
$VaultEnv = Join-Path $env:USERPROFILE ".asrax\credentials.d\vault-kind-nonprod.env"
$tokLine = Get-Content $VaultEnv | Where-Object { $_ -match "^VAULT_TOKEN=" } | Select-Object -First 1
$VaultToken = ($tokLine -replace "^VAULT_TOKEN=", "").Trim().Trim('"')

$env:VAULT_ADDR = "https://vault-preprod.asrax.in"
$env:VAULT_TOKEN = $VaultToken
$env:KUBECONFIG_APPS = $KcA

$py = Join-Path $PSScriptRoot "tmp-fix-apps-csi-preprod.py"
python $py
if ($LASTEXITCODE -ne 0) { throw "python fix failed" }

# Agents stay down
kubectl --kubeconfig $KcA -n am-agents-dev get deploy -o name 2>$null | ForEach-Object {
  kubectl --kubeconfig $KcA -n am-agents-dev scale $_ --replicas=0 2>$null | Out-Null
}

# One clean wave
kubectl --kubeconfig $KcA -n am-apps-dev delete pods --all --force --grace-period=0 2>$null | Out-Null
Start-Sleep -Seconds 5
kubectl --kubeconfig $KcA -n am-apps-dev get deploy -o name | ForEach-Object {
  kubectl --kubeconfig $KcA -n am-apps-dev scale $_ --replicas=1 | Out-Null
}

Write-Host "waiting 50s for mounts..."
Start-Sleep -Seconds 50
Write-Host "---STATUS---"
kubectl --kubeconfig $KcA -n am-apps-dev get pods --no-headers
Write-Host "---FailedMount (last 8)---"
kubectl --kubeconfig $KcA -n am-apps-dev get events --field-selector reason=FailedMount --sort-by=.lastTimestamp 2>&1 | Select-Object -Last 8

Remove-Item Env:VAULT_TOKEN -ErrorAction SilentlyContinue
