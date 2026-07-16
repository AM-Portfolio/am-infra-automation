# Automated Infrastructure & Secrets Sync
# Usage: powershell -File scripts/infra-up.ps1

$E_BOLD = [char]27 + "[1m"
$E_CYAN = [char]27 + "[96m"
$E_GREEN = [char]27 + "[92m"
$E_RESET = [char]27 + "[0m"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$infraDir = Split-Path -Parent $scriptDir
$terraformDir = Join-Path $infraDir "terraform"

Write-Host "`n$E_BOLD$E_CYAN[INFRA-UP] Starting Automated Infrastructure Sync...$E_RESET"

# 1. Terraform Apply
Write-Host "$E_BOLD[1/3] Running Terraform Apply...$E_RESET"
Set-Location $terraformDir
# Use full path to terraform since it's not in global PATH
& "C:\Users\user\OneDrive\Documents\am-repos\am-infra\terraform\terraform.exe" apply -auto-approve

if ($LASTEXITCODE -ne 0) {
    Write-Host "$E_BOLD[ERROR]$E_RESET Terraform apply failed. Aborting sync."
    exit $LASTEXITCODE
}

# 2. Sync Secrets
Write-Host "`n$E_BOLD[2/3] Synchronizing Versioned Secrets...$E_RESET"
Set-Location $scriptDir
python manage_secrets.py --sync

# 3. View Updated Secrets
Write-Host "`n$E_BOLD[3/3] Final Secrets Overview:$E_RESET"
python manage_secrets.py --view

Write-Host "`n$E_BOLD$E_GREEN[COMPLETE] Infrastructure and Secrets are in sync.$E_RESET`n"
