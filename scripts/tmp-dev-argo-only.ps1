# Laptop am-dev-infra: keep Argo CD (+ Traefik for ingress). Tear down DBs, Vault, Keycloak, platform apps.
# Apps Kind left running but scaled down (no local Vault CSI). Prod Keycloak/Vault are external.
$ErrorActionPreference = "Continue"
$KcInfra = Join-Path $env:USERPROFILE ".asrax\kubeconfig.am-dev-infra.yaml"
$KcApps = Join-Path $env:USERPROFILE ".asrax\kubeconfig.am-dev-apps.yaml"

function Scale-AllZero([string]$kc, [string]$ns) {
  $deploys = kubectl --kubeconfig $kc -n $ns get deploy -o name 2>$null
  foreach ($d in $deploys) {
    if (-not $d) { continue }
    kubectl --kubeconfig $kc -n $ns scale $d --replicas=0 2>$null | Out-Null
  }
  $sts = kubectl --kubeconfig $kc -n $ns get sts -o name 2>$null
  foreach ($s in $sts) {
    if (-not $s) { continue }
    kubectl --kubeconfig $kc -n $ns scale $s --replicas=0 2>$null | Out-Null
  }
  $ds = kubectl --kubeconfig $kc -n $ns get ds -o name 2>$null
  foreach ($d in $ds) {
    if (-not $d) { continue }
    kubectl --kubeconfig $kc -n $ns patch $d -p '{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"non-existing\": \"true\"}}}}}' 2>$null | Out-Null
  }
}

# Platform / identity / AI / billing namespaces — delete (keeps argocd)
$deleteNs = @(
  "identity", "vault", "am-ai", "billing", "growthbook", "n8n",
  "notification", "openproject", "temporal", "monitoring"
)
foreach ($ns in $deleteNs) {
  Write-Host "delete ns $ns"
  kubectl --kubeconfig $KcInfra delete ns $ns --wait=false 2>$null | Out-Host
}

# Infra stores: scale to zero (keep ns for Traefik/cloudflared)
Write-Host "scale down infra stores"
$storeWorkloads = @(
  "sts/postgresql", "sts/redis-master", "sts/kafka", "sts/minio", "sts/influxdb-influxdb2",
  "deploy/mongodb", "deploy/pgadmin-pgadmin4", "deploy/mongo-express",
  "deploy/redis-commander", "deploy/kafka-ui", "deploy/kafka-exporter"
)
foreach ($w in $storeWorkloads) {
  kubectl --kubeconfig $KcInfra -n infra scale $w --replicas=0 2>$null | Out-Host
}

# Keep traefik + cloudflared (edge). Ensure present.
kubectl --kubeconfig $KcInfra -n infra get deploy traefik,cloudflared 2>$null | Out-Host

# Apps Kind: scale app/agent deploys to 0 (they pointed at local Vault)
Write-Host "scale down am-dev-apps workloads"
foreach ($ns in @("am-apps-dev", "am-agents-dev")) {
  Scale-AllZero $KcApps $ns
  Write-Host "scaled $ns -> 0"
}

Write-Host "wait argocd ready..."
kubectl --kubeconfig $KcInfra -n argocd rollout status deploy/argocd-server --timeout=180s 2>$null
kubectl --kubeconfig $KcInfra -n argocd get pods,svc 2>&1 | Out-Host

Write-Host "=== remaining non-system infra workloads ==="
kubectl --kubeconfig $KcInfra get deploy,sts -A --no-headers 2>$null |
  Where-Object { $_ -notmatch 'kube-system|local-path|kube-node' } | Out-Host

Write-Host "DEV_ARGO_ONLY_DONE"
Write-Host "Next: point Argo OIDC to prod Keycloak (auth.asrax.in) and use prod Vault; local KC/Vault removed."
