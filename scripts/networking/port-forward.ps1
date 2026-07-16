# Persistent Port-Forwarding Script for Remote VPS Infrastructure
# Usage: powershell -File scripts/port-forward.ps1 -Svc <all|mongodb|postgresql|redis|kafka|influxdb|vault|grafana|headlamp|traefik|web>

param (
    [string]$Svc = "all"
)

# Function to load environment variables from a .env file
function Load-Env {
    param ([string]$filePath)
    if (Test-Path $filePath) {
        Get-Content $filePath | Where-Object { $_ -match "=" -and $_ -notmatch "^#" } | ForEach-Object {
            $name, $value = $_.Split('=', 2)
            $name = $name.Trim()
            $value = $value.Trim().Replace('"', '').Replace("'", "")
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                [Environment]::SetEnvironmentVariable($name, $value, "Process")
            }
        }
    }
}

# Function to start a background port-forward
function Start-PF {
    param (
        [string]$Name,
        [string]$Namespace,
        [string]$Ports,
        [string]$KubeconfigPath
    )
    Start-Process kubectl -ArgumentList "--kubeconfig=`"$KubeconfigPath`" port-forward -n $Namespace svc/$Name $Ports" -WindowStyle Hidden
    Write-Host "[OK] $Name ($Ports)" -ForegroundColor Green
}

# Load environment variables
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Load-Env (Join-Path $scriptDir "..\.env.infra")
Load-Env (Join-Path $scriptDir "..\.env")

# Infrastructure Configuration
$KUBECONFIG = if ($env:VPS_KUBECONFIG) { $env:VPS_KUBECONFIG } else { "c:\Users\user\OneDrive\Documents\am-repos\am-infra\k8s\kubeconfig.vps" }
if ($env:KUBECONFIG_PATH) { $KUBECONFIG = $env:KUBECONFIG_PATH }

# Default Ports
$PORT_MONGO = if ($env:PORT_MONGO) { $env:PORT_MONGO } else { "27017" }
$PORT_POSTGRES = if ($env:PORT_POSTGRES) { $env:PORT_POSTGRES } else { "5432" }
$PORT_REDIS = if ($env:PORT_REDIS) { $env:PORT_REDIS } else { "6379" }
$PORT_KAFKA = if ($env:PORT_KAFKA) { $env:PORT_KAFKA } else { "9092" }
$PORT_INFLUXDB = if ($env:PORT_INFLUXDB) { $env:PORT_INFLUXDB } else { "8086" }
$PORT_VAULT_UI = if ($env:PORT_VAULT_UI) { $env:PORT_VAULT_UI } else { "8200" }
$PORT_GRAFANA = if ($env:PORT_GRAFANA) { $env:PORT_GRAFANA } else { "3000" }
$PORT_HEADLAMP = if ($env:PORT_HEADLAMP) { $env:PORT_HEADLAMP } else { "9093" }
$PORT_TRAEFIK = if ($env:PORT_TRAEFIK_DASHBOARD) { $env:PORT_TRAEFIK_DASHBOARD } else { "8080" }
$PORT_TRAEFIK_WEB = if ($env:PORT_TRAEFIK_WEB) { $env:PORT_TRAEFIK_WEB } else { "8000" }

if ($Svc -eq "all") {
    Write-Host "--- Resetting ALL Port Forwarding (Wait 5s) ---" -ForegroundColor Cyan
    Stop-Process -Name kubectl -ErrorAction SilentlyContinue 
    Start-Sleep -Seconds 5
}

Write-Host "--- Starting Port-Forward: [$Svc] ---" -ForegroundColor Cyan
Write-Host "Using Kubeconfig: $KUBECONFIG" -ForegroundColor Gray

# Databases
if ($Svc -eq "all" -or $Svc -eq "mongodb") { Start-PF "mongodb" "infra" "${PORT_MONGO}:27017" $KUBECONFIG; Start-Sleep -Milliseconds 500 }
if ($Svc -eq "all" -or $Svc -eq "postgresql") { Start-PF "postgresql" "infra" "${PORT_POSTGRES}:5432" $KUBECONFIG; Start-Sleep -Milliseconds 500 }
if ($Svc -eq "all" -or $Svc -eq "redis") { Start-PF "redis" "infra" "${PORT_REDIS}:6379" $KUBECONFIG; Start-Sleep -Milliseconds 500 }
if ($Svc -eq "all" -or $Svc -eq "kafka") { Start-PF "kafka" "infra" "${PORT_KAFKA}:9092" $KUBECONFIG; Start-Sleep -Milliseconds 500 }

# UI Services
if ($Svc -eq "all" -or $Svc -eq "influxdb") { Start-PF "influxdb" "infra" "${PORT_INFLUXDB}:8086" $KUBECONFIG; Start-Sleep -Milliseconds 500 }
if ($Svc -eq "all" -or $Svc -eq "vault") { Start-PF "vault-ui" "vault" "${PORT_VAULT_UI}:8200" $KUBECONFIG; Start-Sleep -Milliseconds 500 }
if ($Svc -eq "all" -or $Svc -eq "grafana") { Start-PF "grafana" "monitoring" "${PORT_GRAFANA}:3000" $KUBECONFIG; Start-Sleep -Milliseconds 500 }
if ($Svc -eq "all" -or $Svc -eq "headlamp") { Start-PF "headlamp" "infra" "${PORT_HEADLAMP}:80" $KUBECONFIG; Start-Sleep -Milliseconds 500 }
if ($Svc -eq "all" -or $Svc -eq "traefik") { Start-PF "traefik" "infra" "${PORT_TRAEFIK}:8080" $KUBECONFIG; Start-Sleep -Milliseconds 500 }
if ($Svc -eq "all" -or $Svc -eq "web") { Start-PF "traefik" "infra" "${PORT_TRAEFIK_WEB}:80" $KUBECONFIG; Start-Sleep -Milliseconds 500 }

Start-Sleep -Seconds 2
$finalCount = (Get-Process kubectl -ErrorAction SilentlyContinue).Count
Write-Host "-------------------------------------------"
Write-Host "Service [$Svc] startup sequence finished."
Write-Host "Active kubectl tunnels: $finalCount (Expected 10 for 'all')" -ForegroundColor $(if ($Svc -eq "all" -and $finalCount -lt 10) { "Red" } else { "Green" })
Write-Host "To stop or reset, use 'npm run pf:stop'." -ForegroundColor Yellow
