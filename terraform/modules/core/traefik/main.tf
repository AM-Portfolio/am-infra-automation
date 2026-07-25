# ==============================================================================
# Traefik Core — Dynamic Routes & Middlewares (Fully Inline, No External Files)
# ==============================================================================
# All route and middleware content previously in traefik/*.yaml is defined here.
# After a successful apply, the traefik/ directory can be safely deleted.
# ==============================================================================

locals {
  # --------------------------------------------------------------------------
  # MIDDLEWARES — absorbed from traefik/middlewares.yaml
  # --------------------------------------------------------------------------
  middlewares_yaml = <<-YAML
    http:
      middlewares:
        # Auth
        forward-auth:
          forwardAuth:
            address: "http://am-auth-tokens.am-apps-preprod.svc.cluster.local:8001/api/v1/validate/me"
            trustForwardHeader: true
            authResponseHeaders:
              - X-User-ID
              - X-Username
              - X-Email
              - X-Roles
        authentik-auth:
          forwardAuth:
            address: "http://authentik-server.identity.svc.cluster.local:80/outpost.goauthentik.io/auth/traefik"
            trustForwardHeader: true
            authResponseHeaders:
              - X-authentik-username
              - X-authentik-groups
              - X-authentik-email
              - X-authentik-name
              - X-authentik-uid
              - X-authentik-jwt
              - X-authentik-meta-jwks
              - X-authentik-meta-outpost
              - X-authentik-meta-provider
              - X-authentik-meta-app
              - X-authentik-meta-version
        infra-rbac-auth:
          forwardAuth:
            address: "http://authentik-server.identity.svc.cluster.local:80/outpost.goauthentik.io/auth/traefik"
            trustForwardHeader: true

        # CORS
        global-cors:
          headers:
            accessControlAllowMethods: ["GET","POST","PUT","DELETE","OPTIONS","PATCH"]
            accessControlAllowHeaders: ["*"]
            accessControlAllowOriginList: ["*"]
            accessControlMaxAge: 100
            addVaryHeader: true

        # Cache
        vary-referer:
          headers:
            customResponseHeaders:
              Vary: "Referer"
              Cache-Control: "no-cache"

        # Path rewriters
        rewrite-users:
          replacePathRegex:
            regex: "^/users/(.*)"
            replacement: "/api/$1"
        rewrite-auth:
          replacePathRegex:
            regex: "^/auth/(.*)"
            replacement: "/api/$1"

        # UI path strippers
        strip-diagnostic:    { stripPrefix: { prefixes: ["/diagnostic"] } }
        strip-market-ui:     { stripPrefix: { prefixes: ["/market-ui"] } }
        strip-trade-ui:      { stripPrefix: { prefixes: ["/trade-ui"] } }
        strip-doc-ui:        { stripPrefix: { prefixes: ["/doc-ui"] } }
        strip-portfolio-ui:  { stripPrefix: { prefixes: ["/portfolio-ui"] } }
        strip-ai-bots-ui:    { stripPrefix: { prefixes: ["/ai-bots-ui"] } }
        strip-headlamp:      { stripPrefix: { prefixes: ["/headlamp"] } }
        strip-prometheus:    { stripPrefix: { prefixes: ["/prometheus"] } }
        strip-grafana:       { stripPrefix: { prefixes: ["/grafana"] } }
        strip-loki:          { stripPrefix: { prefixes: ["/loki"] } }
        strip-vault:         { stripPrefix: { prefixes: ["/vault"] } }
        strip-traefik-dashboard: { stripPrefix: { prefixes: ["/traefik/dashboard"] } }
        strip-terraform-rover:   { stripPrefix: { prefixes: ["/terraform/rover"] } }

        # API strippers
        strip-auth-prefix:   { stripPrefix: { prefixes: ["/auth"] } }
        strip-users:         { stripPrefix: { prefixes: ["/users"] } }
        strip-api-market:    { stripPrefix: { prefixes: ["/api/market"] } }
        strip-api-market-processor: { stripPrefix: { prefixes: ["/api/market/processor"] } }
        strip-api-trade:     { stripPrefix: { prefixes: ["/api/trade"] } }
        strip-api-trade-processor:  { stripPrefix: { prefixes: ["/api/trade/processor"] } }
        strip-api-portfolio: { stripPrefix: { prefixes: ["/api/portfolio"] } }
        strip-api-etf:       { stripPrefix: { prefixes: ["/api/etf"] } }
        strip-api-jobs:      { stripPrefix: { prefixes: ["/api/jobs"] } }
        strip-api-internal-python:
          replacePathRegex:
            regex: "^/api/internal/python/(.*)"
            replacement: "/api/$1"
        strip-api-internal-java:
          replacePathRegex:
            regex: "^/api/internal/java/(.*)"
            replacement: "/api/$1"
        strip-api-doc:
          replacePathRegex:
            regex: "^/api/doc/(.*)"
            replacement: "/api/$1"
        strip-api-doc-processor:
          replacePathRegex:
            regex: "^/api/doc/processor/(.*)"
            replacement: "/api/$1"
        strip-api-ai:
          replacePathRegex:
            regex: "^/api/ai/(.*)"
            replacement: "/api/$1"
        strip-api-ai-analytics:
          replacePathRegex:
            regex: "^/api/ai/analytics/(.*)"
            replacement: "/api/$1"
        strip-api-market-analysis:
          replacePathRegex:
            regex: "^/api/market/analysis/(.*)"
            replacement: "/api/$1"

        # Redirects
        dashboard-redirect:
          redirectRegex:
            regex: "^https?://traefik${var.environment == "prod" ? "" : "-${var.environment}"}.${var.root_domain}/?$"
            replacement: "https://traefik${var.environment == "prod" ? "" : "-${var.environment}"}.${var.root_domain}/dashboard/"
            permanent: true
        add-trailing-slash:
          redirectRegex:
            regex: "^(https?://[^/]+/[^/]+)$"
            replacement: "$1/"
            permanent: true
        force-https-proto:
          headers:
            customRequestHeaders:
              X-Forwarded-Proto: "https"
  YAML

  # --------------------------------------------------------------------------
  # INFRA ROUTES — absorbed from traefik/infra.yaml
  # --------------------------------------------------------------------------
  infra_routes_yaml = <<-YAML
    http:
      routers:
        # ── AM Application APIs ──────────────────────────────────────────
        am-auth:
          rule: "Host(`am.${var.root_domain}`) && PathPrefix(`/auth`)"
          service: am-auth
          priority: 3000
          middlewares: [rewrite-auth, global-cors]
          entryPoints: [web]
        am-users:
          rule: "Host(`am.${var.root_domain}`) && PathPrefix(`/users`)"
          service: am-users
          priority: 3000
          middlewares: [rewrite-users, global-cors]
          entryPoints: [web]
        am-gateway:
          rule: "Host(`am.${var.root_domain}`) && PathPrefix(`/api/v1`)"
          service: am-gateway
          priority: 2000
          middlewares: [global-cors]
          entryPoints: [web]
        internal-python:
          rule: "(Host(`www.${var.root_domain}`) || Host(`localhost`)) && PathPrefix(`/api/internal/python`)"
          service: internal-python
          priority: 1000
          middlewares: [strip-api-internal-python]
          entryPoints: [web]
        internal-java:
          rule: "(Host(`www.${var.root_domain}`) || Host(`localhost`)) && PathPrefix(`/api/internal/java`)"
          service: internal-java
          priority: 1000
          middlewares: [strip-api-internal-java]
          entryPoints: [web]
        market-api:
          rule: "(Host(`www.${var.root_domain}`) || Host(`localhost`)) && PathPrefix(`/api/market`)"
          service: market-api
          priority: 1000
          middlewares: [strip-api-market]
          entryPoints: [web]
        trade-api:
          rule: "(Host(`www.${var.root_domain}`) || Host(`localhost`)) && PathPrefix(`/api/trade`)"
          service: trade-api
          priority: 1000
          middlewares: [strip-api-trade]
          entryPoints: [web]
        portfolio-api:
          rule: "(Host(`www.${var.root_domain}`) || Host(`localhost`)) && PathPrefix(`/api/portfolio`)"
          service: portfolio-api
          priority: 1000
          middlewares: [strip-api-portfolio]
          entryPoints: [web]
        doc-parser-api:
          rule: "(Host(`www.${var.root_domain}`) || Host(`localhost`)) && PathPrefix(`/api/doc`)"
          service: doc-parser-api
          priority: 1000
          middlewares: [strip-api-doc]
          entryPoints: [web]
        ai-bots-api:
          rule: "(Host(`www.${var.root_domain}`) || Host(`localhost`)) && PathPrefix(`/api/ai`)"
          service: ai-bots-api
          priority: 1000
          middlewares: [strip-api-ai]
          entryPoints: [web]
        analysis-api:
          rule: "(Host(`www.${var.root_domain}`) || Host(`localhost`)) && PathPrefix(`/api/v1/analysis`)"
          service: analysis-api
          priority: 1500
          entryPoints: [web]
        analysis-gateway:
          rule: "(Host(`www.${var.root_domain}`) || Host(`localhost`)) && PathPrefix(`/api/v1/gateway`)"
          service: analysis-gateway
          priority: 1500
          entryPoints: [web]

        # Infrastructure subdomains (now migrated to standardized IngressRoute CRDs)

        # ── App UIs (path-based on www) ──────────────────────────────────
        diagnostic-ui:  { rule: "(Host(`www.${var.root_domain}`) || Host(`localhost`)) && PathPrefix(`/diagnostic`)", service: diagnostic-ui, middlewares: [strip-diagnostic, vary-referer], entryPoints: [web] }
        market-ui:      { rule: "(Host(`www.${var.root_domain}`) || Host(`localhost`)) && PathPrefix(`/market-ui`)", service: market-ui, middlewares: [strip-market-ui, vary-referer], entryPoints: [web] }
        trade-ui:       { rule: "(Host(`www.${var.root_domain}`) || Host(`localhost`)) && PathPrefix(`/trade-ui`)", service: trade-ui, middlewares: [strip-trade-ui, vary-referer], entryPoints: [web] }
        doc-ui:         { rule: "(Host(`www.${var.root_domain}`) || Host(`localhost`)) && PathPrefix(`/doc-ui`)", service: doc-ui, middlewares: [strip-doc-ui, vary-referer], entryPoints: [web] }
        portfolio-ui:   { rule: "(Host(`www.${var.root_domain}`) || Host(`localhost`)) && PathPrefix(`/portfolio-ui`)", service: portfolio-ui, middlewares: [strip-portfolio-ui, vary-referer], entryPoints: [web] }
        ai-bots-ui:     { rule: "(Host(`www.${var.root_domain}`) || Host(`localhost`)) && PathPrefix(`/ai-bots-ui`)", service: ai-bots-ui, middlewares: [strip-ai-bots-ui, vary-referer], entryPoints: [web] }
        investment-ui:  { rule: "(Host(`www.${var.root_domain}`) || Host(`localhost`)) && PathPrefix(`/`)", service: investment-ui, priority: 1, entryPoints: [web] }
        headlamp-path:  { rule: "(Host(`am.${var.root_domain}`) || Host(`www.${var.root_domain}`)) && PathPrefix(`/headlamp`)", service: headlamp, priority: 3000, middlewares: [strip-headlamp, vary-referer, authentik-auth], entryPoints: [web] }

      services:
        # AM Apps
        am-auth:       { loadBalancer: { servers: [{ url: "http://am-auth-tokens.am-apps-preprod.svc.cluster.local:8001" }] } }
        am-users:      { loadBalancer: { servers: [{ url: "http://am-user-management.am-apps-preprod.svc.cluster.local:8000" }] } }
        am-gateway:    { loadBalancer: { servers: [{ url: "http://am-api-gateway.am-apps-preprod.svc.cluster.local:8000" }] } }
        # App UIs
        investment-ui: { loadBalancer: { servers: [{ url: "http://host.docker.internal:9000" }] } }
        diagnostic-ui: { loadBalancer: { servers: [{ url: "http://host.docker.internal:9001" }] } }
        market-ui:     { loadBalancer: { servers: [{ url: "http://host.docker.internal:9002" }] } }
        trade-ui:      { loadBalancer: { servers: [{ url: "http://host.docker.internal:9003" }] } }
        doc-ui:        { loadBalancer: { servers: [{ url: "http://host.docker.internal:9004" }] } }
        portfolio-ui:  { loadBalancer: { servers: [{ url: "http://host.docker.internal:9005" }] } }
        ai-bots-ui:    { loadBalancer: { servers: [{ url: "http://host.docker.internal:9006" }] } }
        # APIs
        internal-python:    { loadBalancer: { servers: [{ url: "http://host.docker.internal:8003" }] } }
        internal-java:      { loadBalancer: { servers: [{ url: "http://host.docker.internal:8004" }] } }
        market-api:         { loadBalancer: { servers: [{ url: "http://host.docker.internal:8020" }] } }
        market-processor:   { loadBalancer: { servers: [{ url: "http://host.docker.internal:8021" }] } }
        trade-api:          { loadBalancer: { servers: [{ url: "http://host.docker.internal:8040" }] } }
        trade-processor:    { loadBalancer: { servers: [{ url: "http://host.docker.internal:8041" }] } }
        portfolio-api:      { loadBalancer: { servers: [{ url: "http://host.docker.internal:8060" }] } }
        doc-parser-api:     { loadBalancer: { servers: [{ url: "http://host.docker.internal:8081" }] } }
        doc-processor:      { loadBalancer: { servers: [{ url: "http://host.docker.internal:8082" }] } }
        ai-bots-api:        { loadBalancer: { servers: [{ url: "http://host.docker.internal:8100" }] } }
        ai-bots-analytics:  { loadBalancer: { servers: [{ url: "http://host.docker.internal:8101" }] } }
        analysis-api:       { loadBalancer: { servers: [{ url: "http://host.docker.internal:8090" }] } }
        analysis-gateway:   { loadBalancer: { servers: [{ url: "http://host.docker.internal:8091" }] } }
        market-analysis:    { loadBalancer: { servers: [{ url: "http://market-data-analysis-service:8010" }] } }
        # Infra services
        prometheus-service: { loadBalancer: { servers: [{ url: "http://prometheus-service.monitoring.svc.cluster.local:9090" }] } }
        monitoring-loki:    { loadBalancer: { servers: [{ url: "http://monitoring-loki.monitoring.svc.cluster.local:3100" }] } }
        vault-ui:           { loadBalancer: { servers: [{ url: "http://vault-ui.vault.svc.cluster.local:8200" }] } }
        kafka-ui:           { loadBalancer: { servers: [{ url: "http://kafka-ui.infra.svc.cluster.local:80" }] } }
        headlamp:           { loadBalancer: { servers: [{ url: "http://headlamp.infra.svc.cluster.local:80" }] } }
        influxdb:           { loadBalancer: { servers: [{ url: "http://influxdb-influxdb2.infra.svc.cluster.local:80" }] } }
        mongo-express:      { loadBalancer: { servers: [{ url: "http://mongo-express.infra.svc.cluster.local:8081" }] } }
        pgadmin:            { loadBalancer: { servers: [{ url: "http://pgadmin-pgadmin4.infra.svc.cluster.local:80" }] } }
        redis-insight:      { loadBalancer: { servers: [{ url: "http://redis-commander.infra.svc.cluster.local:80" }] } }
        authentik:          { loadBalancer: { servers: [{ url: "http://authentik-server.identity.svc.cluster.local:80" }] } }
        rover:              { loadBalancer: { servers: [{ url: "http://rover.infra.svc.cluster.local:9000" }] } }
  YAML

  # --------------------------------------------------------------------------
  # APP ROUTES — absorbed from traefik/apps.yaml
  # --------------------------------------------------------------------------
  app_routes_yaml = <<-YAML
    http:
      routers:
        auth-token:
          rule: "Host(`www.${var.root_domain}`) && PathPrefix(`/auth`)"
          service: auth-token
          middlewares: [strip-auth-prefix]
          priority: 100
          entryPoints: [web]
        user-mgmt-register:
          rule: "Host(`www.${var.root_domain}`) && PathPrefix(`/auth/api/v1/auth/register`)"
          service: user-mgmt
          middlewares: [strip-auth-prefix]
          priority: 200
          entryPoints: [web]
        user-mgmt-login:
          rule: "Host(`www.${var.root_domain}`) && PathPrefix(`/auth/api/v1/auth/login`)"
          service: user-mgmt
          middlewares: [strip-auth-prefix]
          priority: 200
          entryPoints: [web]
        user-mgmt-protected:
          rule: "Host(`www.${var.root_domain}`) && PathPrefix(`/users`)"
          service: user-mgmt
          middlewares: [forward-auth, strip-users]
          priority: 100
          entryPoints: [web]
      services:
        auth-token: { loadBalancer: { servers: [{ url: "http://am-auth-tokens.am-apps-preprod.svc.cluster.local:8001" }] } }
        user-mgmt:  { loadBalancer: { servers: [{ url: "http://am-user-management.am-apps-preprod.svc.cluster.local:8002" }] } }
  YAML
}

# ==============================================================================
# ConfigMap — All dynamic routing configs injected inline
# ==============================================================================

resource "kubernetes_config_map" "traefik_dynamic" {
  metadata {
    name      = "traefik-dynamic-config"
    namespace = var.namespace
    labels = {
      managed-by = "terraform"
      component  = "traefik-dynamic"
    }
  }

  data = {
    "middlewares.yaml" = local.middlewares_yaml
    "infra.yaml"       = local.infra_routes_yaml
    "apps.yaml"        = local.app_routes_yaml
  }
}

# ==============================================================================
# Traefik Helm Release
# ==============================================================================

resource "helm_release" "traefik" {
  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  namespace  = var.namespace

  values = [<<-EOT
    deployment:
      podLabels:
        app: traefik

    log:
      level: DEBUG
    accessLog:
      enabled: true

    additionalArguments:
      - "--providers.file.directory=/etc/traefik/dynamic-config/"
      - "--providers.file.watch=true"
      - "--api.dashboard=true"
      - "--api.insecure=true"
      - "--entrypoints.web.forwardedHeaders.insecure=true"
      - "--entrypoints.websecure.forwardedHeaders.insecure=true"
      - "--providers.kubernetescrd.allowcrossnamespace=true"


    ports:
      web:
        exposedPort: 80
        nodePort: 30080
      websecure:
        exposedPort: 443
        nodePort: 30443
      traefik:
        expose:
          default: true
        port: 30990
        nodePort: 30990

    service:
      type: NodePort

    persistence:
      enabled: false

    volumes:
      - name: traefik-dynamic-config
        mountPath: /etc/traefik/dynamic-config
        type: configMap
    EOT
  ]

  depends_on = [kubernetes_config_map.traefik_dynamic]
  timeout    = 900
  wait       = false

  lifecycle {
    prevent_destroy = true
  }
}

# ------------------------------------------------------------------------------
# Traefik Dashboard IngressRoute
# ------------------------------------------------------------------------------

resource "kubectl_manifest" "ingressroute_traefik_dashboard" {
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
  namespace: ${var.namespace}
spec:
  entryPoints:
    - web
    - websecure
  routes:
    - match: Host(`traefik-local.${var.root_domain}`)
      kind: Rule
      services:
        - name: traefik
          port: 8080
      middlewares:
        - name: force-https-proto
        - name: global-cors
YAML

  depends_on = [helm_release.traefik]
}

# ------------------------------------------------------------------------------
# SHARED MIDDLEWARES — Standardized for AM Infrastructure
# ------------------------------------------------------------------------------

resource "kubectl_manifest" "middleware_force_https" {
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: force-https-proto
  namespace: ${var.namespace}
spec:
  headers:
    customRequestHeaders:
      X-Forwarded-Proto: "https"
YAML

  depends_on = [helm_release.traefik]
}

resource "kubectl_manifest" "middleware_global_cors" {
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: global-cors
  namespace: ${var.namespace}
spec:
  headers:
    accessControlAllowMethods: ["GET","POST","PUT","DELETE","OPTIONS","PATCH"]
    accessControlAllowHeaders: ["*"]
    accessControlAllowOriginList: ["*"]
    accessControlMaxAge: 100
    addVaryHeader: true
YAML

  depends_on = [helm_release.traefik]
}

resource "kubectl_manifest" "middleware_vary_referer" {
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: vary-referer
  namespace: ${var.namespace}
spec:
  headers:
    customResponseHeaders:
      Vary: "Referer"
      Cache-Control: "no-cache"
YAML

  depends_on = [helm_release.traefik]
}

resource "kubectl_manifest" "middleware_authentik_auth" {
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: authentik-auth
  namespace: ${var.namespace}
spec:
  forwardAuth:
    address: "http://authentik-server.identity.svc.cluster.local:80/outpost.goauthentik.io/auth/traefik"
    trustForwardHeader: true
    authResponseHeaders:
      - X-authentik-username
      - X-authentik-groups
      - X-authentik-email
      - X-authentik-name
      - X-authentik-uid
      - X-authentik-jwt
      - X-authentik-meta-jwks
      - X-authentik-meta-outpost
      - X-authentik-meta-provider
      - X-authentik-meta-app
      - X-authentik-meta-version
YAML

  depends_on = [helm_release.traefik]
}

resource "kubectl_manifest" "middleware_force_https_redirect" {
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: force-https
  namespace: ${var.namespace}
spec:
  redirectScheme:
    scheme: https
    permanent: true
YAML

  depends_on = [helm_release.traefik]
}
