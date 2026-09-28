# Cloudflare LB — DR primary / Contabo fallback

Apply from the **ops laptop** (or CI) with a CF API token that can manage Load Balancing + DNS + Notifications. Do **not** apply from VPS Kind state.

## Gate: Load Balancing subscription

`asrax.in` is currently on the **Free** zone plan. Creating monitors/pools fails until **Load Balancing** is purchased/enabled on the Cloudflare account (Dashboard → Traffic → Load Balancing → Enable).

Until then, interim DR-primary is **direct CNAME → `asrax-dr-tunnel`** for bare hosts (ops/MCP). Fall-to-Contabo = retarget CNAME to `asrax-prod-tunnel` (see [FAILOVER.md](../../../../docs/kind-fleet-clusters/identity-infra-split/FAILOVER.md)).

```bash
cd terraform/kind-fleet/prod/cloudflare-lb
cp terraform.tfvars.example terraform.tfvars   # fill token + email
terraform init
terraform plan
terraform apply
```

## Direction

| Pool | Role |
|------|------|
| `am-dr-*` | **default** (VPS3 / asrax-dr-tunnel) |
| `am-prod-*` | **fallback** (Contabo / asrax-prod-tunnel) |

`steering_policy = "off"` → ordered failover. When DR is unhealthy, all bare hosts use Contabo.

## No auto-failback

Cloudflare returns traffic to a recovered default pool. To keep Contabo after a DR outage:

1. Notification `am-dr-pool-unhealthy-fall-to-contabo` fires.
2. Set `dr_pool_enabled = false` and `terraform apply` (disables DR origins).
3. After DR + G20 writer soak, set `dr_pool_enabled = true` and apply (human restore).

## Prerequisites

- DR tunnel ingress includes **bare** FQDNs (`tunnel_only_fqdns` on `kind-fleet/dr/edge`).
- DR Traefik IngressRoutes match bare **and** `*-dr` hosts.
- Contabo warm (edge + apps up).
- Prod edge `skip_dns_names` so LB owns bare DNS (this stack creates LBs which attach DNS).

## Drill hosts

`*-dr.asrax.in` remain CNAME → DR tunnel (not on LB).
