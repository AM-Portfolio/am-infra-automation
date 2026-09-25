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
  node_name  = "${var.cluster_name}-control-plane"
  images_csv = join(",", var.images)
}

resource "terraform_data" "crictl_pull" {
  count = var.enabled && length(var.images) > 0 ? 1 : 0

  input = {
    node   = local.node_name
    images = sort(var.images)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KIND_NODE  = local.node_name
      IMAGES_CSV = local.images_csv
    }
    command = <<-BASH
      set -euo pipefail
      node="$${KIND_NODE}"
      if ! docker inspect "$node" >/dev/null 2>&1; then
        echo "KinD node container missing: $node (cluster not running?)" >&2
        exit 1
      fi
      IFS=',' read -r -a imgs <<< "$${IMAGES_CSV}"
      count=0
      for img in "$${imgs[@]}"; do
        img=$(echo "$img" | xargs)
        [ -z "$img" ] && continue
        echo "kind-preload: crictl pull $img on $node"
        ok=0
        for attempt in 1 2 3 4 5; do
          if docker exec "$node" crictl pull "$img"; then
            ok=1
            break
          fi
          echo "kind-preload: retry $attempt for $img"
          sleep $((attempt * 5))
        done
        if [ "$ok" != "1" ]; then
          echo "crictl pull failed after retries: $img" >&2
          exit 1
        fi
        count=$((count + 1))
      done
      echo "kind-preload: ok count=$count node=$node"
    BASH
  }
}

output "node_name" {
  value = local.node_name
}

output "images" {
  value = var.images
}
