# Preload container images into a KinD node's containerd (crictl), not host Docker.
# Host docker pull + kind load is the wrong destination for fleet applies.

terraform {
  required_version = ">= 1.4"
}

variable "cluster_name" {
  type        = string
  description = "KinD cluster name (e.g. am-dev-platform)."
}

variable "images" {
  type        = list(string)
  description = "Fully-qualified image refs to crictl pull on the control-plane node."
}

variable "enabled" {
  type    = bool
  default = true
}

locals {
  node_name = "${var.cluster_name}-control-plane"
  images_csv = join(",", var.images)
}

resource "terraform_data" "crictl_pull" {
  count = var.enabled && length(var.images) > 0 ? 1 : 0

  input = {
    node   = local.node_name
    images = sort(var.images)
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    environment = {
      KIND_NODE  = local.node_name
      IMAGES_CSV = local.images_csv
    }
    command = <<-PS
      $ErrorActionPreference = 'Stop'
      $node = $env:KIND_NODE
      if (-not (docker inspect $node 2>$null)) {
        throw "KinD node container missing: $node (cluster not running?)"
      }
      $imgs = $env:IMAGES_CSV.Split(',') | Where-Object { $_ -and $_.Trim() }
      foreach ($img in $imgs) {
        $img = $img.Trim()
        Write-Output "kind-preload: crictl pull $img on $node"
        docker exec $node crictl pull $img
        if ($LASTEXITCODE -ne 0) { throw "crictl pull failed: $img (exit $LASTEXITCODE)" }
      }
      Write-Output "kind-preload: ok count=$($imgs.Count) node=$node"
    PS
  }
}

output "node_name" {
  value = local.node_name
}

output "images" {
  value = var.images
}
