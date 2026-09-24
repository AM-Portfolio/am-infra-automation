<#
.SYNOPSIS
  Print vault-mappings RHS keys missing from catalog/services.yaml (hints only).

.DESCRIPTION
  Scans sibling AM repos for helm/vault-mappings.yaml and diffs against the
  apps-vault-seed catalog. Does not write secrets. Output is advisory.

.EXAMPLE
  .\gen-catalog-hints.ps1
#>
[CmdletBinding()]
param(
  [string] $ReposRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..\..")).Path,
  [string] $Catalog = (Join-Path $PSScriptRoot "..\catalog\services.yaml")
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Catalog)) { throw "catalog not found: $Catalog" }

# Rough parse: service blocks and key lines under keys:
$catalogText = Get-Content $Catalog -Raw
$catalogKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
[regex]::Matches($catalogText, '(?m)^\s{6}([A-Za-z0-9_]+):') | ForEach-Object {
  [void]$catalogKeys.Add($_.Groups[1].Value)
}

$maps = Get-ChildItem -Path $ReposRoot -Recurse -Filter 'vault-mappings.yaml' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch '\\(\.git|node_modules|target|build|am-gitops)\\' }

Write-Host "Catalog key count (approx): $($catalogKeys.Count)"
Write-Host "Scanning vault-mappings under $ReposRoot ..."
$missing = New-Object System.Collections.Generic.List[string]

foreach ($f in $maps) {
  $rhs = Select-String -Path $f.FullName -Pattern ':\s*"([^"]+)"' | ForEach-Object {
    $_.Matches[0].Groups[1].Value
  } | Where-Object {
    $_ -and $_ -ne '__jaas__' -and $_ -notmatch '^(export |http|<)' -and $_ -notmatch 'VaultKeyName'
  } | Sort-Object -Unique

  foreach ($k in $rhs) {
    if (-not $catalogKeys.Contains($k) -and $k -notmatch '^(host|port|url|username|password|bootstrap_servers)$') {
      $rel = $f.FullName.Replace($ReposRoot, '').TrimStart('\')
      $missing.Add("$k  <<  $rel")
    }
  }
}

$missing | Sort-Object -Unique | ForEach-Object { Write-Host $_ }
Write-Host "Done. Missing-from-catalog hints: $($missing.Count) (infra keys host/url/… intentionally skipped)."
