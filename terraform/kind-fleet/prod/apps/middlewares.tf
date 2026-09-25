# Apps-cluster Traefik middlewares referenced by product helm Ingress annotations:
#   am-apps-prod-global-cors@kubernetescrd
#   am-apps-prod-strip-prefix-apps@kubernetescrd
# Apply via terraform only — do not kubectl-patch these CRs in wave scripts.

resource "kubernetes_manifest" "middleware_global_cors_apps" {
  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = module.naming.middleware_cors
      namespace = kubernetes_namespace.am_apps.metadata[0].name
    }
    spec = {
      headers = {
        accessControlAllowMethods     = ["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"]
        accessControlAllowHeaders     = ["*"]
        accessControlAllowOriginList  = ["*"]
        accessControlAllowCredentials = true
        accessControlMaxAge           = 100
        addVaryHeader                 = true
      }
    }
  }

  depends_on = [kubernetes_namespace.am_apps]
}

resource "kubernetes_manifest" "middleware_strip_prefix_apps" {
  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = module.naming.middleware_strip
      namespace = kubernetes_namespace.am_apps.metadata[0].name
    }
    spec = {
      # Longest prefixes first. Must cover every pathPrefix Ingress that
      # annotates strip-prefix-apps (4c–4g). Do NOT strip /qa.
      stripPrefix = {
        prefixes = [
          "/doc/processor",
          "/v1/streams",
          "/market/parser",
          "/subscription",
          "/notification",
          "/identity",
          "/portfolio",
          "/analysis",
          "/logging",
          "/gateway",
          "/market",
          "/parser",
          "/trade",
          "/email",
          "/gmail",
          "/news",
          "/doc",
          "/am",
          "/mkt-portal",
          "/mkt",
          "/resume",
          "/spt-poc",
          "/ui-test",
        ]
      }
    }
  }

  depends_on = [kubernetes_namespace.am_apps]
}

# asrax-proxy singular rewrite (Ingress annotates rewrite-am-document-singular).
resource "kubernetes_manifest" "middleware_rewrite_am_document_singular" {
  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "rewrite-am-document-singular"
      namespace = kubernetes_namespace.am_apps.metadata[0].name
    }
    spec = {
      replacePathRegex = {
        regex       = "^/am/documents/(.*)"
        replacement = "/am/document/$1"
      }
    }
  }

  depends_on = [kubernetes_namespace.am_apps]
}

resource "kubernetes_manifest" "middleware_global_cors_agents" {
  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = module.naming.middleware_cors
      namespace = kubernetes_namespace.am_agents.metadata[0].name
    }
    spec = {
      headers = {
        accessControlAllowMethods     = ["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"]
        accessControlAllowHeaders     = ["*"]
        accessControlAllowOriginList  = ["*"]
        accessControlAllowCredentials = true
      }
    }
  }

  depends_on = [kubernetes_namespace.am_agents]
}

resource "kubernetes_manifest" "middleware_strip_prefix_agents" {
  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = module.naming.middleware_strip
      namespace = kubernetes_namespace.am_agents.metadata[0].name
    }
    spec = {
      # Agent Ingress paths; do NOT strip /qa (ROOT_PATH=/qa).
      stripPrefix = {
        prefixes = [
          "/mkt-portal",
          "/support",
          "/message",
          "/tools",
          "/resume",
          "/spt-poc",
          "/ui-test",
          "/mkt",
          "/mcp",
          "/db",
          "/ai",
        ]
      }
    }
  }

  depends_on = [kubernetes_namespace.am_agents]
}

# Parser Ingress may annotate parser-strip-prefix separately from env strip.
resource "kubernetes_manifest" "middleware_strip_prefix_parser" {
  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "parser-strip-prefix"
      namespace = kubernetes_namespace.am_apps.metadata[0].name
    }
    spec = {
      stripPrefix = {
        prefixes = ["/market/parser", "/parser"]
      }
    }
  }

  depends_on = [kubernetes_namespace.am_apps]
}
