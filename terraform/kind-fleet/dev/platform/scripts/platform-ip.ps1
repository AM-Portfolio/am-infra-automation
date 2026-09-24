$ErrorActionPreference = 'Stop'
$ip = docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' am-dev-platform-control-plane 2>$null
if (-not $ip) { throw 'am-dev-platform-control-plane not found' }
@{ ip = $ip.Trim() } | ConvertTo-Json -Compress
