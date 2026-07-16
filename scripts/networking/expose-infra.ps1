$ErrorActionPreference = "Stop"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "AM Infrastructure Exposure Script" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# 1. Check Vault Status and Unseal if needed
Write-Host "`n[1/3] Checking Vault status..." -ForegroundColor Yellow
$vaultStatus = kubectl exec vault-0 -n vault -- vault status -format=json | ConvertFrom-Json
if ($vaultStatus.sealed) {
    Write-Host " -> Vault is SEALED. Attempting to unseal..." -ForegroundColor Magenta
    
    # Load keys from k8s\vault\vault-keys.json (relative to script location)
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    $keysFile = Join-Path $scriptPath "..\k8s\vault\vault-keys.json"
    
    if (Test-Path $keysFile) {
        $keys = Get-Content $keysFile | ConvertFrom-Json
        $unsealKey = $keys.unseal_keys_b64[0]
        kubectl exec vault-0 -n vault -- vault operator unseal $unsealKey | Out-Null
        Write-Host " -> Vault has been successfully UNSEALED." -ForegroundColor Green
    } else {
        Write-Error "Vault unseal keys not found at $keysFile. Please unseal manually."
    }
} else {
    Write-Host " -> Vault is already unsealed." -ForegroundColor Green
}

# 2. Wait for Services to be Ready
Write-Host "`n[2/3] Waiting for services to be Ready..." -ForegroundColor Yellow
$namespaces = @("infra", "am-apps-preprod")
foreach ($ns in $namespaces) {
    Write-Host " -> Checking namespace: $ns" -ForegroundColor Gray
    # Wait for all pods in the namespace to be Ready
    # We use a simple loop because 'kubectl wait' can be finicky with newly created pods
    $timeout = 180 # 3 minutes
    $start = Get-Date
    while ($true) {
        $pendingPods = kubectl get pods -n $ns --no-headers | Where-Object { $_ -notmatch "Running|Completed" -or $_ -match "0/" }
        if (-not $pendingPods) {
            Write-Host "    -> All pods in $ns are Ready." -ForegroundColor Green
            break
        }
        
        if (((Get-Date) - $start).TotalSeconds -gt $timeout) {
            Write-Warning "Timed out waiting for pods in $ns. Proceeding anyway..."
            break
        }
        
        Write-Host "    -> Waiting for pods: $($pendingPods.Count) remaining..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 5
    }
}

# 3. Start Port Forwarding
Write-Host "`n[3/3] Starting automatic port-forwarding..." -ForegroundColor Yellow

# Cleanup old kubectl processes
Get-Process -Name "kubectl" -ErrorAction SilentlyContinue | Stop-Process -Force

$services = @(
    @{ Name="mongodb"; Port="27017:27017"; Namespace="infra" },
    @{ Name="postgresql"; Port="5432:5432"; Namespace="infra" },
    @{ Name="redis"; Port="6379:6379"; Namespace="infra" },
    @{ Name="influxdb"; Port="8086:8086"; Namespace="infra" },
    @{ Name="kafka"; Port="9092:9092"; Namespace="infra" },
    @{ Name="zookeeper"; Port="2181:2181"; Namespace="infra" },
    @{ Name="vault-ui"; Port="8200:8200"; Namespace="vault" },
    @{ Name="prometheus-service"; Port="9090:9090"; Namespace="monitoring" },
    @{ Name="grafana"; Port="3000:3000"; Namespace="monitoring" },
    @{ Name="monitoring-loki"; Port="3100:3100"; Namespace="monitoring" },
    @{ Name="traefik"; Port="8000:80"; Namespace="infra" },
    @{ Name="traefik"; Port="9000:9000"; Namespace="infra" }
)

Write-Host "Forwarding Ports in the Background:" -ForegroundColor Magenta

foreach ($svc in $services) {
    $cmd = "kubectl port-forward svc/$($svc.Name) $($svc.Port) -n $($svc.Namespace)"
    Start-Process -NoNewWindow -FilePath "powershell.exe" -ArgumentList "-Command $cmd"
    Write-Host " -> $($svc.Name) on localhost:$($svc.Port.Split(':')[0])" -ForegroundColor Green
}

Write-Host "`nAll systems check out! Services are exposed." -ForegroundColor Cyan
Write-Host "Your passwords are located in am-infra/generated-credentials.txt" -ForegroundColor Yellow
