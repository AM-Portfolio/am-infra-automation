#Requires -Version 5.1
<#
.SYNOPSIS
  One-shot Contabo path repair (tunnel + Argo secret + probe). Prefer auto-heal.

.DESCRIPTION
  Day-2 after Kind restart: host Docker `am-kubeapi-proxy-ensure` (--restart always)
  and in-cluster `kubeapi-proxy-ensure` re-apply the proxy — no manual command.
  This script is break-glass for CF tunnel origin + Contabo cluster secret + probe.

  dig + preprod Contabo Approve both use am-dev-apps via kubeapi-dev.asrax.in.
  1) Ensure kubeapi-proxy on am-dev-apps
  2) Point CF tunnel kubeapi-dev at the proxy
  3) Patch Contabo Argo secret cluster-am-dev-apps
  4) Probe Contabo bearer auth

  Contabo Approve hang / Argo am-dev-apps Failed / Contabo curl kubeapi-dev → CF 502
  while laptop curl → 200: dig cloudflared connectors are stale (proxy+tunnel OK).
  Fix: kubectl --kubeconfig ~/.asrax/kubeconfig.dev.local -n infra rollout restart deploy/cloudflared
  then re-run this script until probe prints bearer=200. See docs/kind-fleet-clusters/KUBEAPI_PROXY.md.

  SoT: kind-fleet/dev/apps/kubeapi-proxy.tf + kubeapi-proxy-ensure.tf

.EXAMPLE
  powershell -File am-infra-automation/scripts/kind-fleet/ensure-kubeapi-dev.ps1
#>
$ErrorActionPreference = "Stop"
$DevKc = Join-Path $env:USERPROFILE ".asrax\kubeconfig.dev"
$DevKcLocal = Join-Path $env:USERPROFILE ".asrax\kubeconfig.dev.local"
$ProdKc = Join-Path $env:USERPROFILE ".asrax\kubeconfig.prod"
$ObsEnv = Join-Path $env:USERPROFILE ".asrax\credentials.d\observability.env"
$TunnelId = "d652365f-bdb2-4382-a4e1-28b628bcf5d3"
$ProxyOrigin = "http://kubeapi-proxy.infra.svc.cluster.local:80"
$TmpDir = Join-Path $env:TEMP "am-kubeapi-ensure"
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null

function Use-Ctx([string]$kc, [string]$want) {
  $env:KUBECONFIG = $kc
  $names = @(kubectl config get-contexts -o name)
  $ctx = $names | Where-Object { $_ -match $want } | Select-Object -First 1
  if (-not $ctx) { throw "No context matching $want in $kc" }
  kubectl config use-context $ctx | Out-Null
}

Write-Host "== 1) kubeapi-proxy on am-dev-apps =="
# Prefer host-only local kubeconfig (tunnel cannot heal itself).
if (Test-Path $DevKcLocal) {
  Use-Ctx $DevKcLocal "dev-apps-local"
} else {
  Use-Ctx $DevKc "dev-apps"
}

$yamlPath = Join-Path $TmpDir "kubeapi-proxy.yaml"
@'
apiVersion: v1
kind: ConfigMap
metadata:
  name: kubeapi-proxy-nginx
  namespace: infra
  labels:
    app: kubeapi-proxy
data:
  nginx.conf: |
    worker_processes 1;
    error_log /dev/stderr warn;
    events { worker_connections 1024; }
    http {
      access_log /dev/stdout;
      server {
        listen 80;
        location / {
          proxy_http_version 1.1;
          proxy_set_header Host $host;
          proxy_set_header Authorization $http_authorization;
          proxy_set_header Connection "";
          proxy_ssl_server_name on;
          proxy_ssl_verify off;
          proxy_buffering off;
          proxy_request_buffering off;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
          proxy_connect_timeout 30s;
          proxy_pass https://kubernetes.default.svc;
        }
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kubeapi-proxy
  namespace: infra
  labels:
    app: kubeapi-proxy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kubeapi-proxy
  template:
    metadata:
      labels:
        app: kubeapi-proxy
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: conf
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
        readinessProbe:
          httpGet:
            path: /version
            port: 80
            httpHeaders:
            - name: Host
              value: kubernetes.default.svc
          initialDelaySeconds: 3
          periodSeconds: 10
      volumes:
      - name: conf
        configMap:
          name: kubeapi-proxy-nginx
---
apiVersion: v1
kind: Service
metadata:
  name: kubeapi-proxy
  namespace: infra
  labels:
    app: kubeapi-proxy
spec:
  selector:
    app: kubeapi-proxy
  ports:
  - name: http
    port: 80
    targetPort: 80
'@ | Set-Content -Path $yamlPath -Encoding utf8
kubectl apply -f $yamlPath
kubectl -n infra rollout status deploy/kubeapi-proxy --timeout=90s

$tokenB64 = kubectl -n kube-system get secret argocd-manager-long-lived-token -o jsonpath="{.data.token}"
if (-not $tokenB64) {
  throw "Missing secret kube-system/argocd-manager-long-lived-token - create long-lived SA token first."
}
$token = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($tokenB64))
$tokenPath = Join-Path $TmpDir "sa.token"
[IO.File]::WriteAllText($tokenPath, $token)

Write-Host "== 2) CF tunnel origin -> kubeapi-proxy =="
Get-Content $ObsEnv | ForEach-Object {
  if ($_ -match '^CLOUDFLARE_API_TOKEN=(.+)$') { $env:CF_TOKEN = $matches[1].Trim() }
  if ($_ -match '^CLOUDFLARE_ACCOUNT_ID=(.+)$') { $env:CF_ACCOUNT = $matches[1].Trim() }
}
if (-not $env:CF_TOKEN -or -not $env:CF_ACCOUNT) { throw "Need CLOUDFLARE_* in $ObsEnv" }

$pyTunnel = Join-Path $TmpDir "set-tunnel.py"
@"
import json, os, urllib.request
t = os.environ['CF_TOKEN']
a = os.environ['CF_ACCOUNT']
tid = '$TunnelId'
origin = '$ProxyOrigin'
url = f'https://api.cloudflare.com/client/v4/accounts/{a}/cfd_tunnel/{tid}/configurations'
req = urllib.request.Request(url, headers={'Authorization': f'Bearer {t}'})
config = json.load(urllib.request.urlopen(req))['result']['config']
new = []
for r in config.get('ingress') or []:
    if r.get('hostname') == 'kubeapi-dev.asrax.in':
        new.append({
            'hostname': 'kubeapi-dev.asrax.in',
            'service': origin,
            'originRequest': {'noTLSVerify': True, 'httpHostHeader': 'kubernetes.default.svc'},
        })
    else:
        new.append(r)
config['ingress'] = new
body = json.dumps({'config': config}).encode()
put = urllib.request.Request(
    url, data=body,
    headers={'Authorization': f'Bearer {t}', 'Content-Type': 'application/json'},
    method='PUT',
)
print('tunnel_ok', json.load(urllib.request.urlopen(put)).get('success'))
"@ | Set-Content -Path $pyTunnel -Encoding utf8
python $pyTunnel

Write-Host "== 3) Contabo cluster-am-dev-apps secret =="
Use-Ctx $ProdKc "prod-infra"
$pySecret = Join-Path $TmpDir "patch-secret.py"
@"
import base64, json, os, subprocess
token = open(r'$tokenPath', encoding='utf-8').read().strip()
cfg = {
    'server': 'https://kubeapi-dev.asrax.in',
    'bearerToken': token,
    'tlsClientConfig': {'insecure': True},
}
patch = json.dumps({'data': {'config': base64.b64encode(json.dumps(cfg).encode()).decode()}})
env = os.environ.copy()
env['KUBECONFIG'] = os.path.expanduser('~/.asrax/kubeconfig.prod')
subprocess.run(['kubectl', 'config', 'use-context', 'prod-infra'], env=env, check=False)
subprocess.run(
    ['kubectl', '-n', 'argocd', 'patch', 'secret', 'cluster-am-dev-apps', '--type', 'merge', '-p', patch],
    env=env, check=True,
)
print('secret_patched')
"@ | Set-Content -Path $pySecret -Encoding utf8
python $pySecret

Write-Host "== 4) Contabo bearer probe =="
Start-Sleep -Seconds 6
$pyProbe = Join-Path $TmpDir "probe.py"
@"
import json, os, subprocess
token = open(r'$tokenPath', encoding='utf-8').read().strip()
env = os.environ.copy()
env['KUBECONFIG'] = os.path.expanduser('~/.asrax/kubeconfig.prod')
subprocess.run(['kubectl', '-n', 'argocd', 'delete', 'pod', 'am-kubeapi-ensure', '--ignore-not-found'], env=env)
subprocess.run(['kubectl', '-n', 'argocd', 'delete', 'secret', 'am-kubeapi-ensure-tok', '--ignore-not-found'], env=env)
subprocess.run(
    ['kubectl', '-n', 'argocd', 'create', 'secret', 'generic', 'am-kubeapi-ensure-tok', '--from-literal=token=' + token],
    env=env, check=True,
)
pod = {
    'apiVersion': 'v1', 'kind': 'Pod',
    'metadata': {'name': 'am-kubeapi-ensure', 'namespace': 'argocd'},
    'spec': {
        'restartPolicy': 'Never',
        'containers': [{
            'name': 'c', 'image': 'curlimages/curl:8.5.0', 'command': ['sleep', '60'],
            'env': [{'name': 'TOK', 'valueFrom': {'secretKeyRef': {'name': 'am-kubeapi-ensure-tok', 'key': 'token'}}}],
        }],
    },
}
subprocess.run(['kubectl', 'apply', '-f', '-'], env=env, input=json.dumps(pod), text=True, check=True)
subprocess.run(['kubectl', '-n', 'argocd', 'wait', '--for=condition=Ready', 'pod/am-kubeapi-ensure', '--timeout=90s'], env=env, check=True)
script = 'echo \"Authorization: Bearer `$TOK\" > /tmp/h.txt; curl -4 -sk --connect-timeout 20 -o /tmp/n -w \"bearer=%{http_code}\\n\" -H @/tmp/h.txt https://kubeapi-dev.asrax.in/api/v1/namespaces; head -c 80 /tmp/n; echo'
p = subprocess.run(
    ['kubectl', '-n', 'argocd', 'exec', 'am-kubeapi-ensure', '--', 'sh', '-c', script],
    env=env, text=True, capture_output=True,
)
print(p.stdout)
subprocess.run(['kubectl', '-n', 'argocd', 'delete', 'pod', 'am-kubeapi-ensure', '--ignore-not-found'], env=env)
subprocess.run(['kubectl', '-n', 'argocd', 'delete', 'secret', 'am-kubeapi-ensure-tok', '--ignore-not-found'], env=env)
if 'bearer=200' not in (p.stdout or ''):
    raise SystemExit('PROBE_FAILED')
print('OK: Contabo -> kubeapi-dev bearer auth works (dig+preprod Contabo Approve path)')
"@ | Set-Content -Path $pyProbe -Encoding utf8
python $pyProbe
if ($LASTEXITCODE -ne 0) { throw "ensure-kubeapi-dev probe failed" }

Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
Write-Host "DONE"
