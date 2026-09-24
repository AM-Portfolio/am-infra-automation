# Host-port bridge for DNS-only names. Not kubectl port-forward (G27).
# Maps host :<std port> → Kind node NodePort on the `kind` Docker network.

locals {
  env = "dev"
  mappings = [
    { name = "postgres", host_port = 5432, target_port = 30432, node = "am-${local.env}-infra-control-plane" },
    { name = "mongo", host_port = 27017, target_port = 30017, node = "am-${local.env}-infra-control-plane" },
    { name = "redis", host_port = 6379, target_port = 30379, node = "am-${local.env}-infra-control-plane" },
    { name = "kafka", host_port = 9092, target_port = 30092, node = "am-${local.env}-infra-control-plane" },
    { name = "influx", host_port = 8086, target_port = 30806, node = "am-${local.env}-infra-control-plane" },
    { name = "minio", host_port = 9000, target_port = 30900, node = "am-${local.env}-infra-control-plane" },
    { name = "vault", host_port = 8200, target_port = 30820, node = "am-${local.env}-infra-control-plane" },
    # Temporal gRPC (platform NodePort) — DNS-only temporal-dev.asrax.in → laptop
    { name = "temporal", host_port = 7233, target_port = 30723, node = "am-${local.env}-platform-control-plane" },
    # Apps Traefik — DNS-only am-dev / corp-dev / asrax-dev hit laptop :80/:443
    { name = "http", host_port = 80, target_port = 30080, node = "am-${local.env}-apps-control-plane" },
    { name = "https", host_port = 443, target_port = 30443, node = "am-${local.env}-apps-control-plane" },
  ]
  docker_ports = join(" ", [for m in local.mappings : "-p ${m.host_port}:${m.host_port}"])
  socat_parts  = [for m in local.mappings : "socat TCP-LISTEN:${m.host_port},fork,reuseaddr TCP:${m.node}:${m.target_port}"]
  socat_inner  = "${join(" & ", local.socat_parts)} & wait"
  nodes_csv    = join(",", distinct([for m in local.mappings : m.node]))
}

resource "null_resource" "port_exposer" {
  triggers = {
    mappings   = jsonencode(local.mappings)
    socat_inner = local.socat_inner
    version    = "5-temporal-grpc"
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    command     = <<-PS
      $ErrorActionPreference = 'Stop'
      $nodes = @('${replace(local.nodes_csv, ",", "','")}')
      foreach ($node in $nodes) {
        $deadline = (Get-Date).AddMinutes(2)
        do {
          $id = docker inspect $node --format '{{.Id}}' 2>$null
          if ($id) { break }
          Start-Sleep 3
        } while ((Get-Date) -lt $deadline)
        if (-not $id) { throw "$node not found (is the kind cluster up?)" }
        Write-Output "kind_node=$node ok"
      }
      $inner = @'
${local.socat_inner}
'@
      $ErrorActionPreference = 'Continue'
      docker rm -f am-port-exposer 2>$null | Out-Null
      $ErrorActionPreference = 'Stop'
      docker run -d --name am-port-exposer ${local.docker_ports} --network kind --restart always --entrypoint /bin/sh alpine/socat -c "$inner"
      Start-Sleep 3
      $st = docker inspect -f "{{.State.Running}}" am-port-exposer
      if ($st -ne "true") { throw "am-port-exposer failed to stay up" }
      Write-Output "am-port-exposer up (stores + apps traefik 80/443)"
    PS
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    command     = "$ErrorActionPreference='Continue'; docker rm -f am-port-exposer 2>$null | Out-Null"
  }
}

output "host_private_ip_note" {
  value = "Cloudflare DNS-only A for *-dev.asrax.in must be the laptop private IP. Exposer maps :80/:443 → apps Traefik NodePorts 30080/30443."
}

output "mappings" {
  value = local.mappings
}
