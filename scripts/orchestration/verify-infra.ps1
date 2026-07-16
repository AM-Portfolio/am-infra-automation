param (
    [string]$Environment = "vps-tunnel"
)

# Standardize colors
$E_BOLD = [char]27 + "[1m"
$E_CYAN = [char]27 + "[96m"
$E_GREEN = [char]27 + "[92m"
$E_RESET = [char]27 + "[0m"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptDir

Write-Host "`n$E_BOLD$E_CYAN[ORCHESTRATOR] Initializing Infrastructure Verification...$E_RESET"

if ($Environment -eq "vps-tunnel") {
    Write-Host "$E_BOLD[1/3] Checking Port Tunnels...$E_RESET"
    
    # Check if a common port (e.g., Vault 8200) is already listening
    $portActive = (Get-NetTCPConnection -LocalPort 8200 -State Listen -ErrorAction SilentlyContinue)
    
    if (-not $portActive) {
        Write-Host "$E_BOLD[!] Tunnels not found. Starting background port-forwarding...$E_RESET"
        # Start the port-forwarding script in a separate background process
        Start-Process powershell -ArgumentList "-NoProfile", "-File", "port-forward.ps1" -WindowStyle Hidden
        
        Write-Host "$E_BOLD[2/3] Waiting 10s for tunnels to stabilize...$E_RESET"
        Start-Sleep -Seconds 10
    } else {
        Write-Host "$E_BOLD[!] Tunnels already active. Skipping initialization.$E_RESET"
        Write-Host "[2/3] Proceeding directly.$E_RESET"
    }
} else {
    Write-Host "[1/3] Skipping tunnels for mode: $Environment"
    Write-Host "[2/3] Proceeding directly."
}

Write-Host "$E_BOLD[3/3] Running Connectivity Checks...$E_RESET"
$env:AM_ENV = $Environment
python check_connectivity.py

Write-Host "`n$E_BOLD$E_GREEN[DONE] Verification complete.$E_RESET"
if ($Environment -eq "vps-tunnel") {
    Write-Host "$($E_CYAN)NOTE: Port tunnels are running in the background. Close hidden PowerShell processes or restart Docker to clear them.$E_RESET`n"
}
