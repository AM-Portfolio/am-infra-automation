# ops modules

Reusable Terraform for Release Glance / fleet reconcile / Argo kubeapi patches.

| Module | Role |
|--------|------|
| [fleet-gaps](fleet-gaps/) | Prometheus → typed gap list (`pin` \| `sync` \| `none`) |
| [fleet-reconcile](fleet-reconcile/) | Consume gaps → GitHub promote + Argo sync (via `am gitops`) |
| [argo-kubeapi-patch](argo-kubeapi-patch/) | Additive CF DNS + Argo cluster secret `server` patch (`kubeapi-*.asrax.in`) |

Agents: prefer `am gitops reconcile` (same gap schema). Contabo consumer: `kind-fleet/prod/release-sync`.

Kubeapi consumers: `kind-fleet/{dev,preprod,prod,dr}/argo-kubeapi/`. Pair with `modules/core/edge` `extra_origin_ingress` for tunnel → Kind API.
