<#
.SYNOPSIS
  Fresh fleet redeploy for apps/agents.

  Phase A — Vault (Terraform only):
    vault-apps seed (apps-vault-seed) + G25 CSI auth via terraform apply.

  Phase B — Workloads (Argo from am-gitops repo checkout only):
    kubectl apply Application YAMLs from {env}/apps + {env}/agents, then
    Argo sync W1→W4 (targetRevision: main). No /tmp Application JSON,
    no _gitops-*.tgz, no scripts/kind-fleet/_fix_* surgery.

  Also: optional Vault backup/wipe, NS wipe, GHCR pin, domain smoke.

.EXAMPLE
  .\fresh-redeploy.ps1 -Env dev -Force
  .\fresh-redeploy.ps1 -Env dev -Force -SkipWipe -SkipPin -StartFromWave W4
#>
[CmdletBinding()]
param(
  [ValidateSet("dev", "prod", "dr")]
  [string] $Env = "dev",
  [switch] $Force,
  [switch] $SkipBackup,
  [switch] $SkipWipe,
  [switch] $SkipTerraform,
  [switch] $SkipPin,
  [switch] $SkipSync,
  [switch] $SkipSmoke,
  [ValidateSet("W1", "W2", "W3", "W4")]
  [string] $StartFromWave = "W1",
  [int] $PerAppTimeoutSec = 480,
  [int] $BatchSize = 3
)

$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
$FleetRoot = Split-Path (Split-Path (Split-Path $ScriptDir -Parent) -Parent) -Parent
. (Join-Path $FleetRoot "fleet-env.ps1")
$f = Get-FleetEnv -Env $Env

$GitopsRoot = "f:\am-repos\am-repos\am-gitops"
$candidate = Join-Path (Split-Path (Split-Path (Split-Path $FleetRoot -Parent) -Parent) -Parent) "am-gitops"
if (Test-Path (Join-Path $candidate "$Env\apps")) { $GitopsRoot = $candidate }

$VaultAddr = $f.VaultUrl
$VaultKeysFile = $f.VaultKeysFile
$AppsKube = $f.AppsKubeconfig
$PlatKube = $f.PlatformKubeconfig
$PinScript = Join-Path $GitopsRoot "scripts\pin-image-tags.ps1"
$HttpsGate = Join-Path $GitopsRoot "scripts\assert-vault-https.ps1"
$SeedScript = Join-Path $ScriptDir "seed-vault-dev-apps.ps1"
$G25Script = Join-Path $ScriptDir "setup-g25-vault-auth.ps1"
$AppsDir = Join-Path $GitopsRoot "$Env\apps"
$AgentsDir = Join-Path $GitopsRoot "$Env\agents"
$Ns = $f.AppsNs
$AgentsNs = $f.AgentsNs
$UiHost = $f.UiHost
$VaultData = $f.VaultDataPrefix
$VaultMeta = $f.VaultMetaPrefix

# W1 - W3 stay in apps; W4 agents live under {env}/agents/
$Wave1 = @(
  "am-gateway", "am-api-gateway", "am-asrax-proxy",
  "am-identity", "am-analysis", "am-market-data"
)
$Wave2 = @(
  "am-portfolio", "am-trade-management-service", "am-oms", "am-parser", "am-news",
  "am-document-processor", "am-modern-ui", "am-user-platform"
)
$Wave3 = @(
  "am-asrax-corp",
  "am-subscription", "am-notification", "am-logging",
  "am-email-extractor", "am-cloudinary-manager"
)
$Wave4 = @(
  "am-support-agent", "am-tool-agent", "am-db-agent",
  "am-qa-agents", "am-mkt-agents", "am-mkt-portal-ui",
  "am-mcp-server", "am-ai-gateway", "am-fin-agent",
  "am-asrax-ui", "n8n"
)

function Get-VaultToken {
  $raw = Get-Content -LiteralPath $VaultKeysFile -Raw
  $raw = $raw.Trim([char]0xFEFF)
  return (ConvertFrom-Json $raw).root_token
}

function Invoke-Vault {
  param(
    [string] $Method,
    [string] $Path,
    [object] $Body = $null
  )
  $tok = Get-VaultToken
  $uri = "$VaultAddr/v1/$Path"
  $headers = @{ "X-Vault-Token" = $tok }
  $params = @{
    Method     = $Method
    Uri        = $uri
    Headers    = $headers
    TimeoutSec = 60
  }
  if ($null -ne $Body) {
    $params.ContentType = "application/json"
    $params.Body = ($Body | ConvertTo-Json -Compress -Depth 20)
  }
  try {
    return Invoke-RestMethod @params
  } catch {
    $resp = $_.Exception.Response
    if ($resp -and [int]$resp.StatusCode -eq 404) { return $null }
    throw "Vault $Method $Path failed: $($_.Exception.Message)"
  }
}

function Get-VaultListKeys {
  param([string] $MetaPath)
  $r = Invoke-Vault -Method GET -Path ($MetaPath + "?list=true")
  if ($null -eq $r) { return @() }
  return @($r.data.keys)
}

function Backup-VaultEnv {
  param([string] $OutDir)
  New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
  $manifest = New-Object System.Collections.Generic.List[object]

  function Walk([string] $Rel) {
    $meta = $VaultMeta
    if ($Rel) { $meta = "$VaultMeta/$Rel".TrimEnd("/") }
    $keys = Get-VaultListKeys -MetaPath $meta
    foreach ($k in $keys) {
      $child = if ($Rel) { "$Rel$k" } else { $k }
      if ($k.EndsWith("/")) {
        Walk $child
      } else {
        $dataPath = "$VaultData/$child"
        $secret = Invoke-Vault -Method GET -Path $dataPath
        if ($null -eq $secret) { continue }
        $file = Join-Path $OutDir (($child -replace "/", "__") + ".json")
        $payload = @{
          path     = "$VaultData/$child"
          data     = $secret.data.data
          metadata = $secret.data.metadata
        }
        ($payload | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $file -Encoding utf8
        $manifest.Add([pscustomobject]@{ path = $payload.path; file = (Split-Path $file -Leaf); keys = @($payload.data.PSObject.Properties.Name).Count })
        Write-Host "  backup $($payload.path) ($($manifest[-1].keys) keys)"
      }
    }
  }

  Walk ""
  $manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutDir "MANIFEST.json") -Encoding utf8
  Write-Host "Backup -> $OutDir ($($manifest.Count) secrets)"
}

function Remove-VaultEnvPaths {
  function WipeList([string] $Rel) {
    $meta = $VaultMeta
    if ($Rel) { $meta = "$VaultMeta/$Rel".TrimEnd("/") }
    $keys = Get-VaultListKeys -MetaPath $meta
    foreach ($k in $keys) {
      $child = if ($Rel) { "$Rel$k" } else { $k }
      if ($k.EndsWith("/")) {
        WipeList $child
      } else {
        $metaPath = "$VaultMeta/$child"
        Write-Host "  delete $metaPath"
        try {
          Invoke-Vault -Method DELETE -Path $metaPath | Out-Null
        } catch {
          Write-Warning "delete failed $metaPath : $($_.Exception.Message)"
        }
      }
    }
  }
  WipeList "infra/"
  WipeList "services/"
}

function Clear-WorkloadNamespace {
  param([string] $TargetNs)
  Write-Host "Clearing workloads in $TargetNs (keep NS + am-backend-sa)..."
  $types = @(
    "deploy,sts,ds,job,cronjob",
    "pod",
    "svc",
    "ing,ingressroute.traefik.io,middleware.traefik.io",
    "secretproviderclass.secrets-store.csi.x-k8s.io",
    "hpa,pdb"
  )
  foreach ($t in $types) {
    cmd /c "kubectl --kubeconfig `"$AppsKube`" -n $TargetNs delete $t --all --wait=false --ignore-not-found 2>nul"
  }
  $deadline = (Get-Date).AddMinutes(2)
  do {
    Start-Sleep 5
    $left = cmd /c "kubectl --kubeconfig `"$AppsKube`" -n $TargetNs get pods --no-headers 2>nul"
    if (-not $left -or $left.Trim().Length -eq 0) { break }
    Write-Host "  waiting pods to terminate in $TargetNs..."
  } while ((Get-Date) -lt $deadline)
  # Force-remove stragglers (CSI/Vault mounts often stick after SPC delete)
  $left = cmd /c "kubectl --kubeconfig `"$AppsKube`" -n $TargetNs get pods -o name 2>nul"
  if ($left -and $left.Trim().Length -gt 0) {
    Write-Warning "force-deleting remaining pods in $TargetNs"
    cmd /c "kubectl --kubeconfig `"$AppsKube`" -n $TargetNs delete pods --all --force --grace-period=0 --ignore-not-found 2>nul"
  }
}

function Invoke-PinImages {
  if (-not (Test-Path -LiteralPath $PinScript)) { throw "missing $PinScript" }
  Write-Host "Pinning GHCR tags into gitops ($Env)..."
  & powershell -NoProfile -ExecutionPolicy Bypass -File $PinScript -Source ghcr -Envs $Env
  if ($LASTEXITCODE -ne 0) { throw "pin-image-tags failed" }
}

function Invoke-HttpsGate {
  if (Test-Path -LiteralPath $HttpsGate) {
    Write-Host "HTTPS-only URL gate..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File $HttpsGate -Env $Env
    if ($LASTEXITCODE -ne 0) { throw "assert-vault-https failed" }
  } else {
    Write-Warning "missing assert-vault-https.ps1 - inline scan"
    $bad = "http" + "://"
    $roots = @((Join-Path $GitopsRoot "$Env\apps"), (Join-Path $GitopsRoot "$Env\agents"), (Join-Path $GitopsRoot "$Env\values-overlays"))
    foreach ($r in $roots) {
      if (-not (Test-Path $r)) { continue }
      $hits = Select-String -Path (Join-Path $r "*.yaml") -Pattern $bad -SimpleMatch -ErrorAction SilentlyContinue
      if ($hits) { throw "plain-http URL found in $r - HTTPS domain only (G26)" }
    }
  }
}

function Resolve-AppYamlDir {
  param([string] $BaseName)
  $inAgents = Join-Path $AgentsDir "$BaseName.yaml"
  if (Test-Path -LiteralPath $inAgents) { return $AgentsDir }
  return $AppsDir
}

function Resolve-AppNs {
  param([string] $BaseName)
  $inAgents = Join-Path $AgentsDir "$BaseName.yaml"
  if (Test-Path -LiteralPath $inAgents) { return $AgentsNs }
  return $Ns
}

function Apply-AllApplications {
  Write-Host "Applying Argo Applications from $AppsDir (server-side) ..."
  cmd /c "kubectl --kubeconfig `"$PlatKube`" apply --server-side --force-conflicts -f `"$AppsDir`""
  if ($LASTEXITCODE -ne 0) { throw "kubectl apply apps failed" }
  if (Test-Path -LiteralPath $AgentsDir) {
    Write-Host "Applying Argo Applications from $AgentsDir (server-side) ..."
    cmd /c "kubectl --kubeconfig `"$PlatKube`" apply --server-side --force-conflicts -f `"$AgentsDir`""
    if ($LASTEXITCODE -ne 0) { throw "kubectl apply agents failed" }
  }
  $agentsRoot = Join-Path $GitopsRoot "$Env\$Env-agents-root.yaml"
  if (Test-Path -LiteralPath $agentsRoot) {
    cmd /c "kubectl --kubeconfig `"$PlatKube`" apply --server-side --force-conflicts -f `"$agentsRoot`""
  }
  $appsRoot = Join-Path $GitopsRoot "$Env\$Env-apps-root.yaml"
  if (Test-Path -LiteralPath $appsRoot) {
    cmd /c "kubectl --kubeconfig `"$PlatKube`" apply --server-side --force-conflicts -f `"$appsRoot`""
  }
}

function Sync-ArgoApp {
  param([string] $AppName)
  $patchFile = Join-Path $env:TEMP "argo-sync-$AppName.json"
  '{"operation":{"initiatedBy":{"username":"fresh-redeploy"},"sync":{"prune":false}}}' |
    Set-Content -LiteralPath $patchFile -Encoding ascii
  cmd /c "kubectl --kubeconfig `"$PlatKube`" -n argocd patch app $AppName --type merge --patch-file `"$patchFile`""
}

function Wait-AppReady {
  param(
    [string] $BaseName,
    [int] $TimeoutSec
  )
  $app = "$BaseName-$Env"
  $targetNs = Resolve-AppNs -BaseName $BaseName
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  Write-Host "  wait $app (ns=$targetNs) ..."
  do {
    Start-Sleep 12
    $st = cmd /c "kubectl --kubeconfig `"$PlatKube`" -n argocd get app $app -o jsonpath=`"{.status.sync.status}/{.status.health.status}`" 2>nul"
    $pods = cmd /c "kubectl --kubeconfig `"$AppsKube`" -n $targetNs get pods -l app.kubernetes.io/instance=$app --no-headers 2>nul"
    Write-Host "    $(Get-Date -Format HH:mm:ss) $st :: $pods"
    $hasFail = ("$pods" -match "CrashLoopBackOff|CreateContainerConfigError")
    $hasPullFail = ("$pods" -match "ImagePullBackOff|ErrImagePull")
    if ($hasFail) {
      cmd /c "kubectl --kubeconfig `"$AppsKube`" -n $targetNs describe pod -l app.kubernetes.io/instance=$app 2>nul" | Select-Object -Last 40
      cmd /c "kubectl --kubeconfig `"$AppsKube`" -n $targetNs logs -l app.kubernetes.io/instance=$app --tail=40 --all-containers 2>nul"
      throw "$app failed: $pods"
    }
    if ($hasPullFail -and ((Get-Date) -gt $deadline.AddSeconds(-120))) {
      throw "$app image pull failed near timeout: $pods"
    }
    $hasReady = ("$pods" -match '1/1\s+Running')
    if ($hasReady -and ("$st" -match '/(Healthy|Progressing)$')) { return }
    if ($hasReady) {
      Write-Warning "$app accepting 1/1 Ready ($st)"
      return
    }
  } while ((Get-Date) -lt $deadline)
  throw "$app timeout after ${TimeoutSec}s (last=$st :: $pods)"
}

function Sync-Wave {
  param(
    [string] $Label,
    [string[]] $Bases,
    [int] $Chunk = 0
  )
  if ($Chunk -le 0) { $Chunk = $Bases.Count }
  $batchNum = 0
  for ($i = 0; $i -lt $Bases.Count; $i += $Chunk) {
    $batchNum++
    $slice = @($Bases[$i..([Math]::Min($i + $Chunk - 1, $Bases.Count - 1))])
    $tag = if ($Chunk -ge $Bases.Count) { $Label } else { "$Label-$batchNum" }
    Write-Host "==== WAVE $tag ($($slice.Count) apps: $($slice -join ', ')) ===="
    foreach ($b in $slice) {
      $dir = Resolve-AppYamlDir -BaseName $b
      $yaml = Join-Path $dir "$b.yaml"
      if (-not (Test-Path -LiteralPath $yaml)) {
        Write-Warning "skip $b - no Application YAML"
        continue
      }
      Sync-ArgoApp -AppName "$b-$Env"
    }
    foreach ($b in $slice) {
      $dir = Resolve-AppYamlDir -BaseName $b
      $yaml = Join-Path $dir "$b.yaml"
      if (-not (Test-Path -LiteralPath $yaml)) { continue }
      Wait-AppReady -BaseName $b -TimeoutSec $PerAppTimeoutSec
    }
    Write-Host "==== WAVE $tag OK ===="
  }
}

function Invoke-Smoke {
  $base = "https://$UiHost"
  $paths = @(
    @{ Name = "modern-ui"; Url = "$base/"; Accept = @(200, 301, 302) },
    @{ Name = "gateway"; Url = "$base/gateway/actuator/health"; Accept = @(200, 401) },
    @{ Name = "identity"; Url = "$base/identity/actuator/health"; Accept = @(200, 401) },
    @{ Name = "market"; Url = "$base/market/actuator/health"; Accept = @(200) },
    @{ Name = "portfolio"; Url = "$base/portfolio/actuator/health"; Accept = @(200) },
    @{ Name = "trade"; Url = "$base/trade/actuator/health"; Accept = @(200) },
    @{ Name = "analysis"; Url = "$base/analysis/actuator/health"; Accept = @(200) },
    @{ Name = "doc"; Url = "$base/doc/processor/actuator/health"; Accept = @(200) },
    @{ Name = "qa-health"; Url = "$base/qa/health"; Accept = @(200) },
    @{ Name = "qa-ui"; Url = "$base/qa/ui/"; Accept = @(200) },
    @{ Name = "corp"; Url = "$base/corp/health"; Accept = @(200) },
    @{ Name = "asrax-ui"; Url = "$base/asrax/"; Accept = @(200, 301, 302) }
  )
  Write-Host "==== SMOKE (domain=$UiHost) ===="
  $fail = 0
  foreach ($p in $paths) {
    try {
      $r = Invoke-WebRequest -Uri $p.Url -UseBasicParsing -TimeoutSec 25
      $code = [int]$r.StatusCode
    } catch {
      $code = 0
      if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    }
    $ok = $p.Accept -contains $code
    Write-Host ("  {0} {1} -> {2}" -f $(if ($ok) { "OK" } else { "FAIL" }), $p.Name, $code)
    if (-not $ok) { $fail++ }
  }
  if ($fail -gt 0) { throw "smoke failed ($fail)" }
}

# --- main ---
if (-not $Force) {
  throw "Refusing to wipe Vault/NS without -Force. Example: .\fresh-redeploy.ps1 -Env $Env -Force"
}

foreach ($p in @($VaultKeysFile, $AppsKube, $PlatKube, $AppsDir)) {
  if (-not (Test-Path -LiteralPath $p)) { throw "missing $p" }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $env:USERPROFILE ".asrax\backups\vault-$Env-apps-$stamp"

Write-Host "=== fresh-redeploy START env=$Env $stamp ==="
Write-Host "GitopsRoot=$GitopsRoot AppsNs=$Ns AgentsNs=$AgentsNs Vault=$VaultAddr"

$allApps = @()
if (Test-Path $AppsDir) {
  $allApps += Get-ChildItem -LiteralPath $AppsDir -Filter *.yaml | ForEach-Object { $_.BaseName }
}
if (Test-Path $AgentsDir) {
  $allApps += Get-ChildItem -LiteralPath $AgentsDir -Filter *.yaml | ForEach-Object { $_.BaseName }
}
$known = @($Wave1 + $Wave2 + $Wave3 + $Wave4)
$WaveExtra = @($allApps | Where-Object { $known -notcontains $_ } | Sort-Object -Unique)
Write-Host "W1=$($Wave1 -join ',')"
Write-Host "W2=$($Wave2 -join ',')"
Write-Host "W3=$($Wave3 -join ',')"
Write-Host "W4=$($Wave4 -join ',')"
if ($WaveExtra.Count -gt 0) { Write-Host "EXTRA(not in waves)=$($WaveExtra -join ',')" }

Invoke-HttpsGate

if (-not $SkipBackup) {
  Write-Host "=== 1. Vault backup ==="
  Backup-VaultEnv -OutDir $backupDir
}

if (-not $SkipWipe) {
  Write-Host "=== 2. Vault wipe $VaultData ==="
  Remove-VaultEnvPaths
  Write-Host "=== 3. Namespace wipe $Ns + $AgentsNs ==="
  Clear-WorkloadNamespace -TargetNs $Ns
  # Agents NS may not exist until terraform apply / first G25 run — never fail wipe on NotFound
  $agentsHit = cmd /c "kubectl --kubeconfig `"$AppsKube`" get ns $AgentsNs -o name 2>nul"
  if ($agentsHit -and "$agentsHit".Trim().Length -gt 0) {
    Clear-WorkloadNamespace -TargetNs $AgentsNs
  } else {
    Write-Host "  skip agents wipe (ns $AgentsNs not present yet)"
  }
}

if (-not $SkipTerraform) {
  Write-Host "=== 4. Terraform vault-apps seed ==="
  if (Test-Path -LiteralPath $SeedScript) {
    & $SeedScript
    if ($LASTEXITCODE -ne 0) { throw "seed-vault failed" }
  } else {
    Write-Warning "missing seed script  -  skip"
  }
}

Write-Host "=== 4b. G25 Vault CSI auth + pull secrets via terraform (env=$Env) ==="
if (-not (Test-Path -LiteralPath $G25Script)) { throw "missing $G25Script" }
& $G25Script -Env $Env
if ($LASTEXITCODE -ne 0) { throw "setup-g25-vault-auth (terraform) failed" }

Write-Host "=== 4c. Ensure Argo CD private repo secrets ==="
$ArgoReposScript = Join-Path $ScriptDir "ensure-argocd-repos.ps1"
if (Test-Path -LiteralPath $ArgoReposScript) {
  & $ArgoReposScript
  if ($LASTEXITCODE -ne 0) { throw "ensure-argocd-repos failed" }
} else {
  Write-Warning "missing ensure-argocd-repos.ps1  -  skip"
}

if (-not $SkipPin) {
  Write-Host "=== 5. Pin image tags (GHCR) ==="
  Invoke-PinImages
}

if (-not $SkipSync) {
  Write-Host "=== 6. Apply Applications + wave sync (StartFromWave=$StartFromWave BatchSize=$BatchSize) ==="
  Apply-AllApplications
  $order = @("W1", "W2", "W3", "W4")
  $startIdx = $order.IndexOf($StartFromWave)
  if ($startIdx -le 0) { Sync-Wave -Label "W1" -Bases $Wave1 }
  if ($startIdx -le 1) { Sync-Wave -Label "W2" -Bases $Wave2 }
  if ($startIdx -le 2) { Sync-Wave -Label "W3" -Bases $Wave3 -Chunk $BatchSize }
  if ($startIdx -le 3) { Sync-Wave -Label "W4" -Bases $Wave4 -Chunk $BatchSize }
  if ($WaveExtra.Count -gt 0 -and $startIdx -le 3) {
    Sync-Wave -Label "EXTRA" -Bases $WaveExtra -Chunk $BatchSize
  }
}

if (-not $SkipSmoke) {
  Write-Host "=== 7. Smoke ==="
  Invoke-Smoke
}

Write-Host "=== fresh-redeploy DONE env=$Env ==="
Write-Host "Vault backup: $backupDir"
exit 0
