<#
.SYNOPSIS
  Ensure Argo CD repository secrets for private AM-Portfolio repos.
#>
[CmdletBinding()]
param(
  [string] $PlatformKubeconfig = (Join-Path $env:USERPROFILE ".asrax\kubeconfig.am-dev-platform.yaml"),
  [string] $SourceSecret = "repo-am-modern-ui",
  [string[]] $Repos = @(
    "https://github.com/AM-Portfolio/am-corp-docs.git",
    "https://github.com/AM-Portfolio/am-mkt-agents.git",
    "https://github.com/AM-Portfolio/am-asrax.git",
    "https://github.com/AM-Portfolio/am-qa-agents.git",
    "https://github.com/AM-Portfolio/am-resume.git",
    "https://github.com/AM-Portfolio/am-market.git",
    "https://github.com/AM-Portfolio/am-trade-management.git",
    "https://github.com/AM-Portfolio/am-agents.git",
    "https://github.com/AM-Portfolio/am-doc-intelligence.git"
  )
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $PlatformKubeconfig)) {
  throw "missing platform kubeconfig: $PlatformKubeconfig"
}

$srcRaw = kubectl --kubeconfig $PlatformKubeconfig -n argocd get secret $SourceSecret -o json 2>$null
if (-not $srcRaw) {
  Write-Warning "source secret $SourceSecret missing - skip Argo repo seed"
  exit 0
}
$src = $srcRaw | ConvertFrom-Json
$user = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$src.data.username))
$pass = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$src.data.password))

foreach ($url in $Repos) {
  $leaf = ([regex]::Replace($url, '\.git$', '') -split "/")[-1]
  $name = "repo-$leaf"
  $body = @{
    apiVersion = "v1"
    kind       = "Secret"
    metadata   = @{
      name      = $name
      namespace = "argocd"
      labels    = @{ "argocd.argoproj.io/secret-type" = "repository" }
    }
    type = "Opaque"
    stringData = @{
      type     = "git"
      url      = $url
      username = $user
      password = $pass
    }
  }
  $tmp = Join-Path $env:TEMP ("argo-{0}.json" -f $name)
  ($body | ConvertTo-Json -Depth 8 -Compress) | Set-Content -LiteralPath $tmp -Encoding utf8
  kubectl --kubeconfig $PlatformKubeconfig apply -f $tmp | Out-Host
  Remove-Item -LiteralPath $tmp -Force
}

Write-Output ("Argo repository secrets ensured for {0} remotes." -f $Repos.Count)
