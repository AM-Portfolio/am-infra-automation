# iam-sso Phase 2 — Headlamp + oauth2-proxy for major UIs without native OIDC.
# Secrets from module.keycloak.oidc_client_secrets (empty → skip proxy).

locals {
  iam_ui_suffix = local.env == "prod" ? "" : "-${local.env}"
  iam_oidc_secret = {
    for k in ["lago", "langfuse", "temporal-web", "litellm", "headlamp", "n8n", "growthbook", "openproject", "novu"] :
    k => try(module.keycloak.oidc_client_secrets[k], "")
  }
}

module "headlamp" {
  source             = "../../../modules/apps/headlamp"
  environment        = local.env
  root_domain        = local.domain
  namespace           = module.namespaces.infra_ns
  issuer_url         = module.keycloak.issuer_url
  oidc_client_id     = "headlamp"
  oidc_client_secret = local.iam_oidc_secret["headlamp"]

  depends_on = [module.keycloak, module.namespaces]
}

module "oauth2_lago" {
  source         = "../../../modules/apps/oauth2-proxy"
  count          = local.iam_oidc_secret["lago"] != "" ? 1 : 0
  name           = "lago"
  namespace      = "billing"
  issuer_url     = module.keycloak.issuer_url
  client_id      = "lago"
  client_secret  = local.iam_oidc_secret["lago"]
  upstream       = "http://lago-front-svc.billing.svc:80"
  redirect_url   = "https://lago${local.iam_ui_suffix}.${local.domain}/oauth2/callback"
  host           = local.gateway_same_cluster ? "lago${local.iam_ui_suffix}.${local.domain}" : ""
  node_port      = local.cross_cluster_routes ? 30831 : 0
  enable_gateway = local.gateway_same_cluster

  depends_on = [module.lago, module.keycloak]
}

module "oauth2_temporal" {
  source         = "../../../modules/apps/oauth2-proxy"
  count          = local.iam_oidc_secret["temporal-web"] != "" ? 1 : 0
  name           = "temporal"
  namespace      = "temporal"
  issuer_url     = module.keycloak.issuer_url
  client_id      = "temporal-web"
  client_secret  = local.iam_oidc_secret["temporal-web"]
  upstream       = "http://temporal-web.temporal.svc:8080"
  redirect_url   = "https://temporal${local.iam_ui_suffix}.${local.domain}/oauth2/callback"
  host           = local.gateway_same_cluster ? "temporal${local.iam_ui_suffix}.${local.domain}" : ""
  node_port      = local.cross_cluster_routes ? 30824 : 0
  enable_gateway = local.gateway_same_cluster

  depends_on = [module.temporal, module.keycloak]
}

module "oauth2_litellm" {
  source         = "../../../modules/apps/oauth2-proxy"
  count          = local.iam_oidc_secret["litellm"] != "" ? 1 : 0
  name           = "litellm"
  namespace      = "am-ai"
  issuer_url     = module.keycloak.issuer_url
  client_id      = "litellm"
  client_secret  = local.iam_oidc_secret["litellm"]
  upstream       = "http://litellm.am-ai.svc:4000"
  redirect_url   = "https://litellm${local.iam_ui_suffix}.${local.domain}/oauth2/callback"
  host           = local.gateway_same_cluster ? "litellm${local.iam_ui_suffix}.${local.domain}" : ""
  node_port      = local.cross_cluster_routes ? 30842 : 0
  enable_gateway = local.gateway_same_cluster

  depends_on = [module.litellm, module.keycloak]
}

module "oauth2_langfuse" {
  source         = "../../../modules/apps/oauth2-proxy"
  count          = local.iam_oidc_secret["langfuse"] != "" ? 1 : 0
  name           = "langfuse"
  namespace      = "am-ai"
  issuer_url     = module.keycloak.issuer_url
  client_id      = "langfuse"
  client_secret  = local.iam_oidc_secret["langfuse"]
  upstream       = "http://langfuse-web.am-ai.svc:3000"
  redirect_url   = "https://langfuse${local.iam_ui_suffix}.${local.domain}/oauth2/callback"
  host           = local.gateway_same_cluster ? "langfuse${local.iam_ui_suffix}.${local.domain}" : ""
  node_port      = local.cross_cluster_routes ? 30843 : 0
  enable_gateway = local.gateway_same_cluster

  depends_on = [module.langfuse, module.keycloak]
}

# When cross-cluster: prefer oauth2-proxy NodePort as bridge backend once proxy exists.
resource "null_resource" "route_oauth2_note" {
  triggers = {
    lago     = try(module.oauth2_lago[0].node_port, 0)
    temporal = try(module.oauth2_temporal[0].node_port, 0)
    litellm  = try(module.oauth2_litellm[0].node_port, 0)
    langfuse = try(module.oauth2_langfuse[0].node_port, 0)
  }
  provisioner "local-exec" {
    command = "echo 'iam-sso: oauth2-proxy NodePorts ready — point cross-cluster-http backends at these when co_locate=false'"
  }
}
