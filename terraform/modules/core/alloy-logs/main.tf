# Grafana Alloy DaemonSet — pod logs → Loki; optional annotation scrape → Prometheus remote_write.
# Labels: cluster, environment (am-obs contract). Cross-cluster URLs must be HTTPS.

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20"
    }
  }
}

variable "namespace" {
  type    = string
  default = "monitoring"
}

variable "create_namespace" {
  type    = bool
  default = true
}

variable "cluster_name" {
  description = "External label cluster= (e.g. am-dev-apps)"
  type        = string
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "loki_push_url" {
  description = "Loki push URL. Cross-cluster must be https://…/loki/api/v1/push; same-cluster ClusterIP http://…svc OK."
  type        = string
}

variable "prometheus_remote_write_url" {
  description = "Optional Prometheus remote_write URL. Empty = logs only. Cross-cluster must be https://…/api/v1/write."
  type        = string
  default     = ""
}

variable "cf_access_client_id" {
  description = "Cloudflare Access Service Token client id for Loki/Prom when Access is enforced."
  type        = string
  default     = ""
  sensitive   = true
}

variable "cf_access_client_secret" {
  description = "Cloudflare Access Service Token client secret."
  type        = string
  default     = ""
  sensitive   = true
}

variable "chart_version" {
  type    = string
  default = "0.9.2"
}

resource "kubernetes_namespace_v1" "monitoring" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
    labels = {
      environment = var.environment
      managed-by  = "terraform"
      role        = "observability"
    }
  }
}

locals {
  metrics_enabled = trimspace(var.prometheus_remote_write_url) != ""
  cf_headers_on   = trimspace(var.cf_access_client_id) != "" && trimspace(var.cf_access_client_secret) != ""

  cf_header_block = local.cf_headers_on ? <<-H
        headers = {
          "CF-Access-Client-Id"     = "${var.cf_access_client_id}"
          "CF-Access-Client-Secret" = "${var.cf_access_client_secret}"
        }
  H
  : ""

  # Cross-cluster FQDNs must be HTTPS; allow in-cluster *.svc.cluster.local over HTTP.
  loki_ok = (
    startswith(var.loki_push_url, "https://") ||
    can(regex("\\.svc\\.cluster\\.local(/|$)", var.loki_push_url))
  )
  prom_ok = (
    !local.metrics_enabled ||
    startswith(var.prometheus_remote_write_url, "https://") ||
    can(regex("\\.svc\\.cluster\\.local(/|$)", var.prometheus_remote_write_url))
  )

  metrics_river_lines = local.metrics_enabled ? [
    "",
    "discovery.kubernetes \"metrics_pods\" {",
    "  role = \"pod\"",
    "}",
    "",
    "discovery.relabel \"metrics_pods\" {",
    "  targets = discovery.kubernetes.metrics_pods.targets",
    "",
    "  rule {",
    "    source_labels = [\"__meta_kubernetes_pod_annotation_prometheus_io_scrape\"]",
    "    action        = \"keep\"",
    "    regex         = \"true\"",
    "  }",
    "  rule {",
    "    source_labels = [\"__meta_kubernetes_pod_annotation_prometheus_io_scheme\"]",
    "    action        = \"replace\"",
    "    target_label  = \"__scheme__\"",
    "    regex         = \"(https?)\"",
    "  }",
    "  rule {",
    "    source_labels = [\"__meta_kubernetes_pod_annotation_prometheus_io_path\"]",
    "    action        = \"replace\"",
    "    target_label  = \"__metrics_path__\"",
    "    regex         = \"(.+)\"",
    "  }",
    "  rule {",
    "    source_labels = [\"__address__\", \"__meta_kubernetes_pod_annotation_prometheus_io_port\"]",
    "    action        = \"replace\"",
    "    regex         = \"(.+?)(?::[0-9]+)?;([0-9]+)\"",
    "    replacement   = \"$1:$2\"",
    "    target_label  = \"__address__\"",
    "  }",
    "  rule {",
    "    source_labels = [\"__meta_kubernetes_namespace\"]",
    "    target_label  = \"namespace\"",
    "  }",
    "  rule {",
    "    source_labels = [\"__meta_kubernetes_pod_name\"]",
    "    target_label  = \"pod\"",
    "  }",
    "  rule {",
    "    source_labels = [\"__meta_kubernetes_pod_container_name\"]",
    "    target_label  = \"container\"",
    "  }",
    "  // Fallback application for Technical Service dropdown when Micrometer omits it",
    "  rule {",
    "    source_labels = [\"__meta_kubernetes_pod_container_name\"]",
    "    regex         = \"^(.+)-dev$\"",
    "    replacement   = \"$1\"",
    "    target_label  = \"application\"",
    "  }",
    "  rule {",
    "    source_labels = [\"application\", \"__meta_kubernetes_pod_container_name\"]",
    "    separator     = \";\"",
    "    regex         = \"^;(.+)$\"",
    "    replacement   = \"$1\"",
    "    target_label  = \"application\"",
    "  }",
    "}",
    "",
    "prometheus.scrape \"annotated_pods\" {",
    "  targets         = discovery.relabel.metrics_pods.output",
    "  forward_to      = [prometheus.remote_write.fleet.receiver]",
    "  scrape_interval = \"30s\"",
    "}",
    "",
    "prometheus.remote_write \"fleet\" {",
    "  endpoint {",
    "    url = \"${var.prometheus_remote_write_url}\"",
    local.cf_headers_on ? "    headers = {\n      \"CF-Access-Client-Id\" = \"${var.cf_access_client_id}\"\n      \"CF-Access-Client-Secret\" = \"${var.cf_access_client_secret}\"\n    }" : "",
    "  }",
    "  external_labels = {",
    "    cluster     = \"${var.cluster_name}\",",
    "    environment = \"${var.environment}\",",
    "  }",
    "}",
  ] : []

  alloy_config = <<-CFG
    logging {
      level  = "info"
      format = "logfmt"
    }

    discovery.kubernetes "pods" {
      role = "pod"
    }

    discovery.relabel "pods" {
      targets = discovery.kubernetes.pods.targets

      rule {
        source_labels = ["__meta_kubernetes_namespace"]
        target_label  = "namespace"
      }
      rule {
        source_labels = ["__meta_kubernetes_pod_name"]
        target_label  = "pod"
      }
      rule {
        source_labels = ["__meta_kubernetes_pod_container_name"]
        target_label  = "container"
      }
      rule {
        source_labels = ["__meta_kubernetes_pod_node_name"]
        target_label  = "node"
      }
      rule {
        target_label = "cluster"
        replacement  = "${var.cluster_name}"
      }
      rule {
        target_label = "environment"
        replacement  = "${var.environment}"
      }
      // Match Technical Service variable (application=)
      rule {
        source_labels = ["__meta_kubernetes_pod_container_name"]
        regex         = "^(.+)-dev$"
        replacement   = "$1"
        target_label  = "application"
      }
      rule {
        source_labels = ["application", "__meta_kubernetes_pod_container_name"]
        separator     = ";"
        regex         = "^;(.+)$"
        replacement   = "$1"
        target_label  = "application"
      }
      rule {
        source_labels = ["__meta_kubernetes_namespace", "__meta_kubernetes_pod_name", "__meta_kubernetes_pod_container_name"]
        separator     = "/"
        target_label  = "job"
      }
      rule {
        source_labels = ["__meta_kubernetes_pod_uid", "__meta_kubernetes_pod_container_name"]
        separator     = "/"
        target_label  = "__path__"
        replacement   = "/var/log/pods/*$1/*.log"
      }
    }

    loki.source.kubernetes "pods" {
      targets    = discovery.relabel.pods.output
      forward_to = [loki.write.default.receiver]
    }

    loki.write "default" {
      endpoint {
        url = "${var.loki_push_url}"
        ${local.cf_headers_on ? "headers = {\n          \"CF-Access-Client-Id\"     = \"${var.cf_access_client_id}\"\n          \"CF-Access-Client-Secret\" = \"${var.cf_access_client_secret}\"\n        }" : ""}
      }
      external_labels = {
        cluster     = "${var.cluster_name}",
        environment = "${var.environment}",
      }
    }
    ${join("\n", local.metrics_river_lines)}
  CFG
}

resource "terraform_data" "url_guard" {
  input = {
    loki = var.loki_push_url
    prom = var.prometheus_remote_write_url
  }
  lifecycle {
    precondition {
      condition     = local.loki_ok
      error_message = "loki_push_url must be https://… or in-cluster *.svc.cluster.local (no http://NodePort)."
    }
    precondition {
      condition     = local.prom_ok
      error_message = "prometheus_remote_write_url must be https://… or in-cluster *.svc.cluster.local when set."
    }
  }
}

resource "helm_release" "alloy" {
  name             = "alloy"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "alloy"
  namespace        = var.namespace
  version          = var.chart_version
  create_namespace = false

  values = [yamlencode({
    alloy = {
      configMap = {
        content = local.alloy_config
      }
      mounts = {
        varlog = true
      }
    }
    controller = {
      type = "daemonset"
    }
    serviceAccount = {
      create = true
    }
    rbac = {
      create = true
    }
    crds = {
      create = false
    }
  })]

  depends_on = [
    kubernetes_namespace_v1.monitoring,
    terraform_data.url_guard,
  ]
  wait    = true
  timeout = 600
}

output "namespace" {
  value = var.namespace
}

output "metrics_enabled" {
  value = local.metrics_enabled
}
