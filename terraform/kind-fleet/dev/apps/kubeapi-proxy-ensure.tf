# Host Docker ensure for kubeapi-proxy after Kind recreate (like am-port-exposer).
# In-cluster healer alone is wiped with Kind; this container survives on the host.

locals {
  kubeapi_ensure_name = "am-kubeapi-proxy-ensure"
  kubeapi_apps_cp     = "am-dev-apps-control-plane"
  kubeapi_manifest    = abspath("${path.module}/../../../modules/ops/kubeapi-proxy/kubeapi-proxy.yaml")
  kubeapi_loop        = abspath("${path.module}/../../scripts/kubeapi-proxy-ensure-loop.sh")
  # Prefer host-only local kubeconfig; tunnel file cannot heal the API path.
  kubeapi_kc          = fileexists("${pathexpand("~")}/.asrax/kubeconfig.dev.local") ? "${pathexpand("~")}/.asrax/kubeconfig.dev.local" : "${pathexpand("~")}/.asrax/kubeconfig.dev"
}

resource "null_resource" "kubeapi_proxy_ensure" {
  triggers = {
    manifest_sha   = filesha256(local.kubeapi_manifest)
    loop_sha       = filesha256(local.kubeapi_loop)
    version        = "2-loop-script"
    apps_cp        = local.kubeapi_apps_cp
    container_name = local.kubeapi_ensure_name
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    command     = <<-PS
      $ErrorActionPreference = 'Stop'
      $name = '${local.kubeapi_ensure_name}'
      $cp = '${local.kubeapi_apps_cp}'
      $manifest = (Resolve-Path '${replace(local.kubeapi_manifest, "'", "''")}').Path
      $loop = (Resolve-Path '${replace(local.kubeapi_loop, "'", "''")}').Path
      $kcLocal = $env:USERPROFILE + '\.asrax\kubeconfig.dev.local'
      $kcTunnel = $env:USERPROFILE + '\.asrax\kubeconfig.dev'
      $kc = if (Test-Path $kcLocal) { $kcLocal } else { $kcTunnel }
      if (-not (Test-Path $kc)) { throw "missing kubeconfig $kc" }

      $deadline = (Get-Date).AddMinutes(5)
      do {
        $id = docker inspect $cp --format '{{.Id}}' 2>$null
        if ($id) { break }
        Start-Sleep 3
      } while ((Get-Date) -lt $deadline)
      if (-not $id) { throw "$cp not found (is Kind am-dev-apps up?)" }

      $ErrorActionPreference = 'Continue'
      docker rm -f $name 2>$null | Out-Null
      $ErrorActionPreference = 'Stop'

      docker run -d --name $name --restart always --network kind `
        -e APPS_CP=$cp -e INTERVAL=30 -e MANIFEST=/manifests/kubeapi-proxy.yaml `
        -v "$${kc}:/kubeconfig.host:ro" `
        -v "$${manifest}:/manifests/kubeapi-proxy.yaml:ro" `
        -v "$${loop}:/ensure-loop.sh:ro" `
        --entrypoint /bin/bash alpine/k8s:1.31.4 `
        /ensure-loop.sh

      Start-Sleep 5
      $st = docker inspect -f '{{.State.Running}}' $name
      if ($st -ne 'true') {
        docker logs $name 2>&1 | Select-Object -Last 40
        throw "$name failed to stay up"
      }
      Write-Output "$name up (restart=always) — auto-applies kubeapi-proxy when Kind is ready"
    PS
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    command     = "$ErrorActionPreference='Continue'; docker rm -f ${self.triggers.container_name} 2>$null | Out-Null"
  }
}

output "kubeapi_proxy_ensure_container" {
  value       = local.kubeapi_ensure_name
  description = "Host Docker container that re-applies kubeapi-proxy after Kind restart (no manual ensure script)."
}
