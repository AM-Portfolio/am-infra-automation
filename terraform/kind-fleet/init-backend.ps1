# Writes backend.hcl for a kind-fleet stack so state stays on the host.
# Usage: .\init-backend.ps1 -Env dev -Role infra
#        .\init-backend.ps1 -Env dev -Role vault-apps
# Then: terraform -chdir=<stack> init -backend-config=backend.hcl
# Does not terraform apply or kind create.

param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("dev", "prod", "dr", "obs")]
  [string]$Env,

  [Parameter(Mandatory = $true)]
  [ValidateSet("infra", "apps", "platform", "obs", "vault-apps", "stores", "edge", "exposer", "warmup")]
  [string]$Role
)

if ($Env -eq "obs" -and $Role -ne "obs") {
  throw "obs host only has cluster_role=obs (name am-obs)"
}
if ($Env -ne "obs" -and $Role -eq "obs") {
  throw "cluster_role=obs is only valid on env=obs"
}

$here = $PSScriptRoot
$stack = if ($Env -eq "obs") { Join-Path $here "obs" } else { Join-Path (Join-Path $here $Env) $Role }

if (-not (Test-Path $stack)) {
  throw "stack folder missing: $stack"
}

if ($Env -eq "dev") {
  $path = Join-Path $HOME ".asrax\tfstate\dev\$Role\terraform.tfstate"
} elseif ($Env -eq "obs") {
  $path = "/data/am-state/terraform/obs/terraform.tfstate"
} else {
  $path = "/data/am-state/terraform/$Env/$Role/terraform.tfstate"
}

$pathUnix = ($path -replace "\\", "/")
Set-Content -Path (Join-Path $stack "backend.hcl") -Value "path = `"$pathUnix`"" -Encoding utf8
Write-Output "wrote $($stack)\backend.hcl -> $pathUnix"
