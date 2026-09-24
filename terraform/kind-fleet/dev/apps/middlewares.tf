# Apps-cluster Traefik middlewares referenced by gitops Ingress annotations:
#   {appsNs}-{env}-global-cors@kubernetescrd
#   {agentsNs}-{env}-global-cors@kubernetescrd
# Do NOT strip /qa — am-qa-agents uses ROOT_PATH=/qa (portal at /qa/ui).

resource "kubernetes_manifest" "middleware_global_cors_apps" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = module.naming.middleware_cors
      namespace = kubernetes_namespace.am_apps.metadata[0].name
    }
    spec = {
      headers = {
        accessControlAllowMethods    = ["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"]
        accessControlAllowHeaders    = ["*"]
        accessControlAllowOriginList = ["*"]
        accessControlAllowCredentials = true
      }
    }
  }

  depends_on = [kubernetes_namespace.am_apps]
}

resource "kubernetes_manifest" "middleware_strip_prefix_apps" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = module.naming.middleware_strip
      namespace = kubernetes_namespace.am_apps.metadata[0].name
    }
    spec = {
      # Longest prefixes first. Matches Ingress paths that annotate
      # `{appsNs}-{env}-strip-prefix@kubernetescrd`. Do NOT strip /qa.
      stripPrefix = {
        prefixes = [
          "/doc/processor",
          "/v1/streams",
          "/market/parser",
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

resource "kubernetes_manifest" "middleware_global_cors_agents" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = module.naming.middleware_cors
      namespace = kubernetes_namespace.am_agents.metadata[0].name
    }
    spec = {
      headers = {
        accessControlAllowMethods    = ["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"]
        accessControlAllowHeaders    = ["*"]
        accessControlAllowOriginList = ["*"]
        accessControlAllowCredentials = true
      }
    }
  }

  depends_on = [kubernetes_namespace.am_agents]
}

# Parser Ingress annotates `{appsNs}-parser-strip-prefix@kubernetescrd` (separate from env strip).
resource "kubernetes_manifest" "middleware_strip_prefix_parser" {
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

resource "kubernetes_manifest" "middleware_strip_prefix_agents" {
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
