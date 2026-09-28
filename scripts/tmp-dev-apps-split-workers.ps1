# Join apps + agents workers onto live am-dev-apps Kind (preprod-style layout).
# Namespaces: am-apps-{dev,preprod} / am-agents-{dev,preprod}
# Labels: workload=apps | workload=agents
# Does NOT terraform-apply the Kind cluster (that would recreate).
$ErrorActionPreference = "Continue"
$Cluster = "am-dev-apps"
$Kc = Join-Path $env:USERPROFILE ".asrax\kubeconfig.am-dev-apps.yaml"
$Image = (docker inspect "${Cluster}-control-plane" --format "{{.Config.Image}}").Trim()
if (-not $Image) { throw "control-plane not running" }

function Ensure-Ns([string]$Name, [string]$Workload, [string]$EnvLabel) {
  kubectl --kubeconfig $Kc create ns $Name --dry-run=client -o yaml |
    kubectl --kubeconfig $Kc apply -f - | Out-Null
  kubectl --kubeconfig $Kc label ns $Name --overwrite `
    "environment=$EnvLabel" "role=$Workload" "workload=$Workload" "managed-by=script" | Out-Null
  # SA + pull secrets cloned from am-apps-dev when present
  $srcNs = if ($Workload -eq "apps") { "am-apps-dev" } else { "am-agents-dev" }
  kubectl --kubeconfig $Kc -n $Name create sa am-backend-sa --dry-run=client -o yaml |
    kubectl --kubeconfig $Kc apply -f - | Out-Null
  foreach ($sec in @("ghcr-creds", "github-registry-secret", "regcred")) {
    $exists = kubectl --kubeconfig $Kc -n $srcNs get secret $sec -o name 2>$null
    if ($exists) {
      kubectl --kubeconfig $Kc -n $srcNs get secret $sec -o json |
        python -c "import json,sys; d=json.load(sys.stdin); d['metadata']={'name':d['metadata']['name'],'namespace':'$Name'}; d.pop('resourceVersion',None); d.pop('uid',None); d.pop('creationTimestamp',None); print(json.dumps(d))" |
        kubectl --kubeconfig $Kc apply -f - | Out-Null
    }
  }
  # Patch SA imagePullSecrets
  $patch = '{"imagePullSecrets":[{"name":"ghcr-creds"},{"name":"github-registry-secret"},{"name":"regcred"}]}'
  kubectl --kubeconfig $Kc -n $Name patch sa am-backend-sa --type merge -p $patch 2>$null | Out-Null
}

function Join-Worker([string]$Suffix, [string]$Workload) {
  $name = "${Cluster}-${Suffix}"
  $ready = kubectl --kubeconfig $Kc get node $name -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}" 2>$null
  if ($ready -eq "True") {
    Write-Host "node $name already Ready"
    kubectl --kubeconfig $Kc label node $name --overwrite "workload=$Workload" "role=$Workload" | Out-Null
    return
  }
  $running = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $name }
  if (-not $running) {
    Write-Host "creating container $name ($Image)"
    docker run -d --name $name --hostname $name --privileged `
      --security-opt seccomp=unconfined --tmpfs /tmp --tmpfs /run `
      -v /lib/modules:/lib/modules:ro `
      --network kind `
      --label io.x-k8s.kind.cluster=$Cluster `
      --label "io.x-k8s.kind.role=worker" `
      $Image | Out-Null
    Start-Sleep 8
  } else {
    docker start $name | Out-Null
    Start-Sleep 3
  }

  $join = docker exec "${Cluster}-control-plane" kubeadm token create --print-join-command --ttl 1h
  if (-not $join) { throw "failed to create kubeadm join command" }
  Write-Host "joining $name as workload=$Workload"
  # Kind nodes: skip preflight; use containerd socket
  docker exec $name bash -lc "kubeadm reset -f >/dev/null 2>&1 || true; $join --node-name $name --ignore-preflight-errors=all --cri-socket=unix:///run/containerd/containerd.sock" 2>&1 | Select-Object -Last 20
  # wait Ready
  for ($i = 0; $i -lt 60; $i++) {
    $st = kubectl --kubeconfig $Kc get node $name -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}" 2>$null
    if ($st -eq "True") { break }
    Start-Sleep 3
  }
  kubectl --kubeconfig $Kc label node $name --overwrite "workload=$Workload" "role=$Workload" | Out-Null
  Write-Host "node $name labeled workload=$Workload"
}

Write-Host "=== scale down workloads to free RAM for new Kind workers ==="
foreach ($ns in @("am-apps-dev", "am-agents-dev")) {
  $deploys = @(kubectl --kubeconfig $Kc -n $ns get deploy -o name 2>$null)
  foreach ($d in $deploys) {
    if (-not $d) { continue }
    cmd /c "kubectl --kubeconfig `"$Kc`" -n $ns scale $d --replicas=0 >nul 2>&1"
  }
}
Start-Sleep 10

Write-Host "=== join workers ==="
Join-Worker "worker-apps" "apps"
Join-Worker "worker-agents" "agents"

Write-Host "=== namespaces (dev + preprod style) ==="
Ensure-Ns "am-apps-dev" "apps" "dev"
Ensure-Ns "am-agents-dev" "agents" "dev"
Ensure-Ns "am-apps-preprod" "apps" "preprod"
Ensure-Ns "am-agents-preprod" "agents" "preprod"

Write-Host "=== pin Deployments/StatefulSets to workers ==="
python -c @"
import json, subprocess, os
kc = os.path.expanduser(r'~\.asrax\kubeconfig.am-dev-apps.yaml')
pairs = [
  ('am-apps-dev', 'apps'),
  ('am-agents-dev', 'agents'),
  ('am-apps-preprod', 'apps'),
  ('am-agents-preprod', 'agents'),
]
for ns, wl in pairs:
  for kind in ('deploy', 'sts'):
    try:
      out = subprocess.check_output(['kubectl','--kubeconfig',kc,'-n',ns,'get',kind,'-o','json'], stderr=subprocess.DEVNULL)
    except Exception:
      continue
    data = json.loads(out)
    for item in data.get('items', []):
      name = item['metadata']['name']
      patch = {
        'spec': {
          'template': {
            'spec': {
              'nodeSelector': {'workload': wl},
              'tolerations': item['spec']['template']['spec'].get('tolerations', []),
            }
          }
        }
      }
      subprocess.call(['kubectl','--kubeconfig',kc,'-n',ns,'patch',kind,name,'--type','merge','-p',json.dumps(patch)])
      print('pinned', kind, ns, name, '->', wl)
"@

# Prefer workers for app/agent pods via nodeSelector only (no CP taint — CSI/Traefik stay schedulable).
Write-Host "=== scale apps/agents back (dev only; preprod NS left empty) ==="
foreach ($ns in @("am-apps-dev", "am-agents-dev")) {
  $deploys = @(kubectl --kubeconfig $Kc -n $ns get deploy -o name 2>$null)
  foreach ($d in $deploys) {
    if (-not $d) { continue }
    cmd /c "kubectl --kubeconfig `"$Kc`" -n $ns scale $d --replicas=1 >nul 2>&1"
  }
}

Write-Host "=== nodes ==="
kubectl --kubeconfig $Kc get nodes -L workload,role
Write-Host "done"
