# ------------------------------------------------------------------------------
# Zero-Trust Micro-segmentation (NetworkPolicies)
# ------------------------------------------------------------------------------

terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}



# 1. Default Deny - Blocks ALL ingress traffic inside the namespace by default
resource "kubernetes_network_policy" "default_deny" {
  count = length(var.namespaces)

  metadata {
    name      = "default-deny-ingress"
    namespace = var.namespaces[count.index]
  }

  spec {
    pod_selector {} # Empty selector means ALL pods in the namespace
    policy_types = ["Ingress"]
    
    # We do NOT define an 'ingress' block here, meaning all ingress is dropped.
    # Exeptions must be explicitly created via specific allow policies.
  }
}

# 2. Allow Core DNS (Required for any pod to resolve names)
resource "kubernetes_network_policy" "allow_dns" {
  count = length(var.namespaces)

  metadata {
    name      = "allow-dns-egress"
    namespace = var.namespaces[count.index]
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]
    
    egress {
      ports {
        port     = 53
        protocol = "UDP"
      }
      ports {
        port     = 53
        protocol = "TCP"
      }
    }
  }
}
