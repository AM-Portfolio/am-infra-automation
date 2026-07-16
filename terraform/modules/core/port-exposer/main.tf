# ==============================================================================
# Provider-Agnostic Port Exposer (Pure Terraform Bridge)
# ==============================================================================
# Uses local-exec to manage a standalone Docker container. 
# This avoids Terraform provider versioning issues while remaining managed 
# by Terraform's lifecycle.
# ==============================================================================

locals {
  docker_ports = join(" ", [for m in var.mappings : "-p ${m.host_port}:${m.host_port}"])
  
  # Build a single robust shell command to start multiple socat relays in parallel
  socat_cmd = join(" & ", [
    for m in var.mappings :
    "echo '🔌 Forwarding ${m.name}: Host ${m.host_port} -> Cluster ${m.target_host}:${m.target_port}'; socat -d -d TCP-LISTEN:${m.host_port},fork,reuseaddr TCP:${m.target_host}:${m.target_port}"
  ])
}

resource "null_resource" "exposer_bridge" {
  # Trigger re-creation if mappings change, logic is updated, or forced
  triggers = {
    mappings       = jsonencode(var.mappings)
    container_name = var.container_name
    version        = "6"
  }

  provisioner "local-exec" {
    command = <<EOT
      docker rm -f ${var.container_name} 2>$null
      docker run -d --name ${var.container_name} --entrypoint /bin/sh `
        ${local.docker_ports} `
        --network kind `
        --restart always `
        alpine/socat `
        -c "echo '🌐 AM Bridge Online...'; ${local.socat_cmd} & wait"
      
      Write-Host "⏳ Waiting for bridge stability (5s)..."
      Start-Sleep -s 5
      
      $status = (docker inspect -f '{{.State.Running}}' ${var.container_name})
      if ($status -eq "true") {
        Write-Host "✅ Bridge is UP and stable."
      } else {
        Write-Error "❌ Bridge failed to stay UP. Check logs with 'docker logs ${var.container_name}'"
        exit 1
      }
    EOT
    interpreter = ["powershell", "-Command"]
  }

  provisioner "local-exec" {
    when    = destroy
    command = "docker rm -f ${self.triggers.container_name} || true"
  }
}
