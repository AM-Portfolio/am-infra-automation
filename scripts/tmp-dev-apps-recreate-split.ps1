# Recreate am-dev-apps Kind as CP + apps worker + agents worker, then bootstrap NS/SA.
$ErrorActionPreference = "Continue"
$Cluster = "am-dev-apps"
$Kc = Join-Path $env:USERPROFILE ".asrax\kubeconfig.am-dev-apps.yaml"
$Config = Join-Path $PSScriptRoot "tmp-dev-apps-kind-split.yaml"
$Bak = Join-Path $env:TEMP "am-dev-apps-ns-bak"

Write-Host "=== kind delete $Cluster ==="
kind delete cluster --name $Cluster 2>&1
Start-Sleep 3

Write-Host "=== kind create (split workers) ==="
kind create cluster --config $Config --kubeconfig $Kc 2>&1
if ($LASTEXITCODE -ne 0) { throw "kind create failed" }

# Also merge into default kind kubeconfig path used by some tools
kind export kubeconfig --name $Cluster --kubeconfig $Kc 2>&1 | Out-Null

Write-Host "=== wait nodes Ready ==="
kubectl --kubeconfig $Kc wait --for=condition=Ready node --all --timeout=180s 2>&1
kubectl --kubeconfig $Kc get nodes -L workload,role

# Label by hostname pattern if kubeadm labels missed
$nodes = kubectl --kubeconfig $Kc get nodes -o json | ConvertFrom-Json
foreach ($n in $nodes.items) {
  $name = $n.metadata.name
  if ($name -match "worker" -and $name -match "2$|worker2|worker-2") {
    # kind names workers as am-dev-apps-worker, am-dev-apps-worker2
  }
}
# Kind names: <cluster>-worker, <cluster>-worker2 (order = config order)
$w = @(kubectl --kubeconfig $Kc get nodes -o name | ForEach-Object { $_.Replace("node/","") } | Where-Object { $_ -notmatch "control-plane" } | Sort-Object)
if ($w.Count -ge 2) {
  kubectl --kubeconfig $Kc label node $w[0] --overwrite workload=apps role=apps
  kubectl --kubeconfig $Kc label node $w[1] --overwrite workload=agents role=agents
  Write-Host "labeled $($w[0])=apps $($w[1])=agents"
} elseif ($w.Count -eq 1) {
  kubectl --kubeconfig $Kc label node $w[0] --overwrite workload=apps role=apps
}

function Ensure-Ns([string]$Name, [string]$Workload, [string]$EnvLabel) {
  kubectl --kubeconfig $Kc create ns $Name --dry-run=client -o yaml | kubectl --kubeconfig $Kc apply -f - | Out-Null
  kubectl --kubeconfig $Kc label ns $Name --overwrite "environment=$EnvLabel" "role=$Workload" "workload=$Workload" "managed-by=script" | Out-Null
  kubectl --kubeconfig $Kc -n $Name create sa am-backend-sa --dry-run=client -o yaml | kubectl --kubeconfig $Kc apply -f - | Out-Null
}

Write-Host "=== namespaces ==="
Ensure-Ns "am-apps-dev" "apps" "dev"
Ensure-Ns "am-agents-dev" "agents" "dev"
Ensure-Ns "am-apps-preprod" "apps" "preprod"
Ensure-Ns "am-agents-preprod" "agents" "preprod"
kubectl --kubeconfig $Kc create ns edge --dry-run=client -o yaml | kubectl --kubeconfig $Kc apply -f - | Out-Null

Write-Host "=== restore pull secrets ==="
if (Test-Path $Bak) {
  Get-ChildItem $Bak -Filter "*.yaml" | ForEach-Object {
    $raw = Get-Content $_.FullName -Raw
    # rewrite namespace from filename prefix
    if ($_.Name -match '^(am-apps-dev|am-agents-dev)-') {
      $srcNs = $Matches[1]
      foreach ($dst in @($srcNs, ($srcNs -replace '-dev$','-preprod'))) {
        $yaml = $raw -replace "namespace: $srcNs", "namespace: $dst"
        $yaml = $yaml -replace "(?m)^  (resourceVersion|uid|creationTimestamp):.*\r?\n", ""
        $tmp = Join-Path $env:TEMP ("sec-" + $dst + "-" + $_.Name)
        Set-Content -Path $tmp -Value $yaml -Encoding utf8
        kubectl --kubeconfig $Kc apply -f $tmp 2>&1 | Out-Null
      }
    }
  }
}

foreach ($ns in @("am-apps-dev","am-agents-dev","am-apps-preprod","am-agents-preprod")) {
  $patch = '{"imagePullSecrets":[{"name":"ghcr-creds"},{"name":"github-registry-secret"},{"name":"regcred"}]}'
  kubectl --kubeconfig $Kc -n $ns patch sa am-backend-sa --type merge -p $patch 2>$null | Out-Null
  # default SA too
  kubectl --kubeconfig $Kc -n $ns patch sa default --type merge -p $patch 2>$null | Out-Null
}

Write-Host "=== install secrets-store CSI + vault provider (helm) ==="
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts 2>$null
helm repo add hashicorp https://helm.releases.hashicorp.com 2>$null
helm repo update 2>&1 | Select-Object -Last 3
helm upgrade --install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver `
  --namespace kube-system --kubeconfig $Kc `
  --set syncSecret.enabled=true --set enableSecretRotation=true `
  --wait --timeout 180s 2>&1 | Select-Object -Last 15
helm upgrade --install vault-csi-provider hashicorp/vault `
  --namespace kube-system --kubeconfig $Kc `
  --set injector.enabled=false --set server.enabled=false `
  --set csi.enabled=true --set "csi.agent.enabled=true" `
  --wait --timeout 180s 2>&1 | Select-Object -Last 15

Write-Host "=== nodes final ==="
kubectl --kubeconfig $Kc get nodes -L workload,role
kubectl --kubeconfig $Kc get ns | Select-String "am-|edge"
Write-Host "DONE - Argo on am-dev-infra must re-register/sync apps into this cluster"
