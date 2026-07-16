# ── Cloudflare Module Outputs ────────────────────────────────────────────────
# These provide connectivity information for downstream layers.

# In Token-First mode, these are placeholder values since the Tunnel 
# is managed externally via the Cloudflare Dashboard.

output "tunnel_id" {
  description = "The unique ID of the Cloudflare Tunnel"
  value       = "managed-via-token"
}

output "tunnel_cname" {
  description = "The CNAME assigned to the tunnel endpoint"
  value       = "${var.root_domain}.cfargotunnel.com"
}
