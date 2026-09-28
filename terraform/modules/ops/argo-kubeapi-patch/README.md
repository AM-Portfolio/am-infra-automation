# argo-kubeapi-patch

Additive Terraform patch for Contabo Argo → Kind API over stable hostnames.

| Piece | Behavior |
|-------|----------|
| Cloudflare DNS | Proxied CNAME `kubeapi-{env}.asrax.in` → existing tunnel (allow_overwrite) |
| Argo secret | `kubectl patch` **only** `data.server` on existing cluster secret — never delete/recreate |
| Tunnel ingress | **Not** owned here (would fight edge). Set `extra_origin_ingress` on `modules/core/edge` |

## Consumers

`terraform/kind-fleet/{dev,preprod,prod,dr}/argo-kubeapi/`

```bash
cd terraform/kind-fleet/dev/argo-kubeapi
terraform init
terraform plan
# DNS only until enable_argo_patch=true + argo_kubeconfig set:
terraform apply -var='enable_argo_patch=true' -var='argo_kubeconfig=/path/to/contabo-argo.kubeconfig'
```

## Guards

- `kubeapi_server_url` must match `https://kubeapi-….asrax.in` (no IP / no :26443).
- Patch fails if the Argo cluster secret is missing (fail closed).
- Destroying this module does **not** delete the Argo Secret or tunnel.

## Phase 0

Probe DNS/TCP:443/`/version` before enabling `enable_argo_patch`.
