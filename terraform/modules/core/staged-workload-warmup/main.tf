# Post-restart staged warmup: gates then ALL deploy/sts in every non-system NS,
# in batches. Discovers workloads live - no hardcoded app lists.

terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

resource "null_resource" "warmup" {
  triggers = {
    generation = var.warmup_generation
    batch_size = tostring(var.batch_size)
    env        = var.environment
    namespaces = var.namespaces
    exclude    = var.exclude_namespaces
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-File"]
    command     = "${path.module}/scripts/warmup.ps1"
    environment = {
      WARMUP_ENV               = var.environment
      WARMUP_BATCH_SIZE        = tostring(var.batch_size)
      WARMUP_PER_APP_TIMEOUT   = tostring(var.per_app_timeout_sec)
      WARMUP_GATE_TIMEOUT      = tostring(var.gate_timeout_sec)
      WARMUP_GENERATION        = var.warmup_generation
      WARMUP_SKIP_GATES        = var.skip_gates ? "1" : "0"
      WARMUP_SKIP_WORKLOADS    = var.skip_workloads ? "1" : "0"
      WARMUP_SKIP_BRIDGE       = var.skip_bridge_refresh ? "1" : "0"
      WARMUP_NAMESPACES        = var.namespaces
      WARMUP_EXCLUDE_NAMESPACES = var.exclude_namespaces
      WARMUP_KUBECONFIG        = var.kubeconfig
    }
  }
}

output "warmup_generation" {
  value = var.warmup_generation
}

output "batch_size" {
  value = var.batch_size
}
