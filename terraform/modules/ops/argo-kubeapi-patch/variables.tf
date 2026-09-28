variable "enabled" {
  type        = bool
  default     = true
  description = "Master switch for this patch module."
}

variable "root_domain" {
  type    = string
  default = "asrax.in"
}

variable "kubeapi_hostname" {
  type        = string
  description = "Public hostname for Kind API (e.g. kubeapi-dev.asrax.in). Argo cluster server must use https:// this host."
}

variable "tunnel_id" {
  type        = string
  default     = ""
  description = "Existing Cloudflare tunnel ID. DNS CNAME target = {tunnel_id}.cfargotunnel.com."
}

variable "cloudflare_account_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "manage_dns" {
  type        = bool
  default     = true
  description = "Create proxied CNAME for kubeapi_hostname → tunnel (additive; allow_overwrite)."
}

variable "argo_cluster_secret_name" {
  type        = string
  description = "Existing Argo CD cluster secret in argocd NS (e.g. cluster-am-dev-apps). Patched in place — never deleted."
}

variable "argo_namespace" {
  type    = string
  default = "argocd"
}

variable "kubeapi_server_url" {
  type        = string
  description = "Full Argo cluster server URL to patch in (https://kubeapi-….asrax.in). No IP:port."
}

variable "enable_argo_patch" {
  type        = bool
  default     = false
  description = "When true, kubectl-patch the cluster secret server field. Default false for plan-only."
}

variable "argo_kubeconfig" {
  type        = string
  default     = ""
  description = "Kubeconfig path that can patch secrets in Argo NS (Contabo main or DR Argo host)."
}

variable "argo_kube_context" {
  type        = string
  default     = ""
  description = "Optional kubectl --context for Argo host cluster."
}
