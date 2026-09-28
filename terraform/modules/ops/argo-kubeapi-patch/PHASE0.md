# Phase 0 / live probe results

Updated after TF DNS apply + tunnel ingress merge + Argo secret patches (2026-09-28).

| Host | DNS | GET /version | Notes |
|------|-----|--------------|-------|
| kubeapi-dev.asrax.in | ok (CF) | **HTTP 200** `v1.27.3` | dig tunnel healthy; Argo `cluster-am-dev-apps` server patched |
| kubeapi-preprod.asrax.in | ok (CF) | HTTP 530 / CF 1033 | `asrax-preprod-tunnel` **down** — DNS+ingress ready, wait for tunnel |
| kubeapi-prod.asrax.in | ok (CF) | **HTTP 200** `v1.27.3` | prod tunnel; Argo `cluster-am-prod-apps` server patched |
| kubeapi-dr.asrax.in | ok (CF) | **HTTP 200** `v1.27.3` | DR tunnel ingress added |
| am-dev.asrax.in (negative) | ok | HTTP 200 HTML/app | **not** kube API |

## Applied

1. `terraform apply` dig/preprod/prod/dr `argo-kubeapi` (DNS only).
2. CF tunnel ingress additive rules → `https://kubernetes.default.svc` (noTLSVerify).
3. Contabo main Argo secret patches: `cluster-am-dev-apps`, `cluster-am-prod-apps`.
4. Socat / old IP path left in place (not deleted).

## Next operator checks

- Contabo Argo UI: `am-dev-apps` / `am-prod-apps` connection Successful.
- Bring up `asrax-preprod-tunnel` then register/patch `cluster-am-vps-nonprod` → `https://kubeapi-preprod.asrax.in`.
- Smoke Contabo Approve dig (trade-management / gateways).
