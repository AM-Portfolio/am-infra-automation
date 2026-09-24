# ------------------------------------------------------------------------------
# MinIO Routing & Gateway (Traefik IngressRoutes)
# ------------------------------------------------------------------------------

locals {
  domain_suffix = var.environment == "prod" ? "" : "-${var.environment}"
}

# 1. Console Routing (User Interface)
resource "kubectl_manifest" "ingressroute_minio_console" {
  count     = var.enable_gateway ? 1 : 0
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: minio-console
  namespace: ${var.namespace}
spec:
  entryPoints:
    - web
    - websecure
  routes:
    - match: Host(`minio${local.domain_suffix}.${var.root_domain}`)
      kind: Rule
      services:
        - name: minio
          port: 9001
YAML
}

# 2. API Routing (S3 Endpoint)
resource "kubectl_manifest" "ingressroute_minio_api" {
  count     = var.enable_gateway ? 1 : 0
  yaml_body = <<YAML
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: minio-api
  namespace: ${var.namespace}
spec:
  entryPoints:
    - web
    - websecure
  routes:
    - match: Host(`s3${local.domain_suffix}.${var.root_domain}`)
      kind: Rule
      services:
        - name: minio
          port: 9000
YAML
}
