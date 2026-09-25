<#
.SYNOPSIS
  Shared naming for kind-fleet scripts: one -Env knob → NS, Vault, hosts, kubeconfigs.

.EXAMPLE
  . "$PSScriptRoot\fleet-env.ps1"
  $f = Get-FleetEnv -Env dev
  $f.AppsNs   # am-apps-dev
#>

function Get-FleetEnv {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "preprod", "prod", "dr")]
    [string] $Env = "dev"
  )

  $domain = "asrax.in"
  # Prod public vault hostname historically omits the env infix.
  $vaultHost = if ($Env -eq "prod") { "vault.$domain" } else { "vault-$Env.$domain" }
  $uiHost = if ($Env -eq "prod") { "am.$domain" } else { "am-$Env.$domain" }
  $authHost = if ($Env -eq "prod") { "auth.$domain" } else { "auth-$Env.$domain" }

  return [pscustomobject]@{
    Env              = $Env
    Domain           = $domain
    AppsNs           = "am-apps-$Env"
    AgentsNs         = "am-agents-$Env"
    BoundNamespaces  = @("am-apps-$Env", "am-agents-$Env")
    VaultUrl         = "https://$vaultHost"
    VaultHost        = $vaultHost
    VaultKeysFile    = (Join-Path $env:USERPROFILE ".asrax\vault-$Env-infra.json")
    VaultPolicyName  = "am-apps-read"
    VaultAuthMount   = "kubernetes-apps"
    VaultRole        = "am-backend-role"
    VaultDataPrefix  = "apps/data/$Env"
    VaultMetaPrefix  = "apps/metadata/$Env"
    UiHost           = $uiHost
    AuthHost         = $authHost
    AppsKubeconfig   = (Join-Path $env:USERPROFILE ".asrax\kubeconfig.am-$Env-apps.yaml")
    InfraKubeconfig  = (Join-Path $env:USERPROFILE ".asrax\kubeconfig.am-$Env-infra.yaml")
    PlatformKubeconfig = (Join-Path $env:USERPROFILE ".asrax\kubeconfig.am-$Env-platform.yaml")
    AppsClusterName  = "am-$Env-apps"
    MiddlewareCors   = if ($Env -in @("prod", "preprod")) { "global-cors" } else { "$Env-global-cors" }
    MiddlewareStrip  = if ($Env -in @("prod", "preprod")) { "strip-prefix-apps" } else { "$Env-strip-prefix" }
    GitopsEnvDir     = $Env
  }
}

function Get-FleetVaultPolicyHcl {
  param(
    [Parameter(Mandatory = $true)]
    [string] $Env
  )
  # Paths are env-scoped; policy name stays am-apps-read (role binds per cluster).
  return @"
path "apps/data/$Env/*" { capabilities = ["create","read","update","list"] }
path "apps/metadata/$Env/*" { capabilities = ["list"] }
path "apps/data/$Env/runtime/*" { capabilities = ["create","read","update","list"] }
path "apps/metadata/$Env/runtime/*" { capabilities = ["list"] }
path "secret/data/$Env/*" { capabilities = ["read","list"] }
path "secret/metadata/$Env/*" { capabilities = ["list"] }
"@
}
