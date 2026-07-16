# ------------------------------------------------------------------------------
# MinIO SSO — Native OIDC (Direct Integration)
# ------------------------------------------------------------------------------

resource "random_password" "minio_client_secret" {
  length  = 32
  special = true
}

resource "authentik_provider_oauth2" "minio" {
  name          = "minio"
  client_id     = "minio"
  client_secret = random_password.minio_client_secret.result
  
  authorization_flow  = data.authentik_flow.default_provider_authorization_implicit_consent.id
  
  # Standard Authentik OIDC Scopes (UUIDs)
  property_mappings = [
    "547c2009-5d7c-470a-9654-076c8244502c", # openid
    "a74ee01e-5ed3-49d6-950a-b42179e3131f", # email
    "f6e927c8-acc9-4a9b-bb3d-2fe9d0a779f9"  # profile
  ]

  # MinIO Console redirect URI
  redirect_uris = [
    "https://minio-${var.environment}.${var.root_domain}/oauth_callback",
    "http://localhost:9001/oauth_callback"
  ]
}

resource "authentik_application" "minio" {
  name              = "MinIO"
  slug              = "minio"
  protocol_provider = authentik_provider_oauth2.minio.id
  meta_icon         = "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/minio.png"
  
  group = "Infrastructure"
}

# --- Persist OIDC Secrets to Vault for MinIO consumption ---
resource "vault_kv_secret_v2" "minio_oidc" {
  mount = "secret"
  name  = "${var.environment}/infra/oidc-minio"

  data_json = jsonencode({
    client_id     = authentik_provider_oauth2.minio.client_id
    client_secret = authentik_provider_oauth2.minio.client_secret
    issuer_url    = "https://authentik-local.${var.root_domain}"
  })
}
