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
    # Browsers reject ACAO "*" when credentials are true (Flutter web).
    # Keep localhost + 127.0.0.1 for local flutter run (port 9000/3000).
    spec = {
      headers = {
        accessControlAllowMethods = ["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"]
        accessControlAllowHeaders = [
          "Content-Type",
          "Authorization",
          "X-Requested-With",
          "Accept",
          "Origin",
          "Idempotency-Key",
          "X-Request-ID",
          "X-Trace-ID",
        ]
        accessControlAllowOriginList = [
          "http://localhost:3000",
          "http://localhost:9000",
          "http://127.0.0.1:3000",
          "http://127.0.0.1:9000",
          "https://am-dev.asrax.in",
          "https://am-preprod.asrax.in",
        ]
        accessControlAllowCredentials = true
        accessControlMaxAge           = 100
        addVaryHeader                 = true
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
        accessControlAllowMethods = ["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"]
        accessControlAllowHeaders = [
          "Content-Type",
          "Authorization",
          "X-Requested-With",
          "Accept",
          "Origin",
          "Idempotency-Key",
          "X-Request-ID",
          "X-Trace-ID",
        ]
        accessControlAllowOriginList = [
          "http://localhost:3000",
          "http://localhost:9000",
          "http://127.0.0.1:3000",
          "http://127.0.0.1:9000",
          "https://am-dev.asrax.in",
          "https://am-preprod.asrax.in",
        ]
        accessControlAllowCredentials = true
        accessControlMaxAge           = 100
        addVaryHeader                 = true
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
