# kubeapi-proxy (Contabo → laptop Kind)

Contabo main Argo talks to laptop Kind **`am-dev-apps`** through Cloudflare Tunnel hostname **`kubeapi-dev.asrax.in`**.

**Never** point the tunnel at `https://kubernetes.default.svc` directly. Cloudflare / TLS termination breaks Kubernetes bearer auth → Contabo Approve **401 / 500 / 403** (`failed to discover server resources`).

## Working path

```text
Contabo Argo API
  → https://kubeapi-dev.asrax.in
  → Cloudflare Tunnel (asrax-dev)
  → cloudflared on am-dev-apps
  → http://kubeapi-proxy.infra.svc.cluster.local:80   (HTTP nginx)
  → https://kubernetes.default.svc
```

| Piece | SoT |
|-------|-----|
| Proxy Deployment/Service | `terraform/modules/ops/kubeapi-proxy/` |
| Dev TF | `terraform/kind-fleet/dev/apps/kubeapi-proxy.tf` |
| Tunnel origin | dig/edge `kubeapi_kind_api_origin` → proxy URL + `httpHostHeader: kubernetes.default.svc` |
| Contabo cluster secret | `cluster-am-dev-apps` server `https://kubeapi-dev.asrax.in` |
| Env landing | **dev** + **preprod** apps both on `am-dev-apps` (see am-gitops `DEV_ON_CONTABO.md`) |

nginx must keep long watches alive (`proxy_read_timeout 3600s`, buffering off) or Contabo returns **504**.

## Self-heal (no manual command after Kind restart)

Same idea as `am-port-exposer`:

| Healer | What | Survives Kind wipe? |
|--------|------|---------------------|
| Host Docker **`am-kubeapi-proxy-ensure`** (`--restart always`) | Waits for Kind API, `kubectl apply` proxy YAML if not Ready | **Yes** |
| In-cluster **`infra/kubeapi-proxy-ensure`** | Loop: if `kubeapi-proxy` not ready → re-apply | No (wiped with cluster; host ensure restores) |

Scripts:

- `terraform/kind-fleet/scripts/ensure-kubeapi-proxy.sh` — start/recreate host container
- `terraform/kind-fleet/scripts/kubeapi-proxy-ensure-loop.sh` — loop inside the container
- Manifests: `terraform/modules/ops/kubeapi-proxy/kubeapi-proxy.yaml` (+ `kubeapi-proxy-ensure.yaml`)
- Dig TF host ensure: `terraform/kind-fleet/dev/apps/kubeapi-proxy-ensure.tf`
- VPS boot: `kind-fleet-boot.sh` step `ensure-kubeapi-proxy`

Break-glass (tunnel origin + Contabo secret + probe only):  
`scripts/kind-fleet/ensure-kubeapi-dev.ps1`

## Verify

```powershell
# Proxy + ensure up
kubectl --kubeconfig ~/.asrax/kubeconfig.dev -n infra get deploy,pods -l 'app in (kubeapi-proxy,kubeapi-proxy-ensure)'
docker inspect -f '{{.State.Running}}' am-kubeapi-proxy-ensure

# Public API (200 on /version without auth is OK)
curl.exe -4 -sk -o NUL -w '%{http_code}\n' https://kubeapi-dev.asrax.in/version

# Contabo apps can see the cluster
kubectl --kubeconfig ~/.asrax/kubeconfig.prod -n argocd get app -l '...'  # or am-ai-gateway-dev
```

Bearer discover from Contabo must return **200** with a non-empty `APIGroupList` on `/apis`. Empty/unknown → Contabo Approve PUT fails with **403** `failed to discover server resources`.

## CI symptom map

| Contabo Approve | Likely cause |
|-----------------|--------------|
| **401** | Tunnel still HTTPS to kube API (no kubeapi-proxy) |
| **500** EOF / server version | Kind / tunnel blip — retries in `am-pipelines` `argo-api-lib.sh` |
| **500** `lookup kubeapi-dev… server misbehaving` | Contabo Kind **CoreDNS** upstream (Docker `172.18.0.1`) broken — pin `forward . 8.8.8.8 8.8.4.4` via `terraform/kind-fleet/scripts/ensure-kind-host-dns.sh` (also sets Docker `daemon.json` dns + Kind node `/etc/resolv.conf`) |
| **403** discover zero resources | Same path broken or secret token stale; fix proxy+tunnel then refresh `cluster-am-dev-apps` |
| **504** | nginx/CF watch timeout — ensure long `proxy_read_timeout` |

After path is healthy, **ImagePullBackOff** on the destination is often the same Docker/Tailscale DNS failure on the Kind node (`lookup ghcr.io on 172.18.0.1:53 server misbehaving`). Run as root on the VPS:

```bash
ENV=prod bash terraform/kind-fleet/scripts/ensure-kind-host-dns.sh --restart-docker
```

That writes durable `dns: ["8.8.8.8","8.8.4.4"]` (survives Tailscale/host resolv churn), patches live Kind node resolv, and pins CoreDNS forward. Hooked from `kind-fleet-boot.sh` (without docker restart). Separate GHCR **403** after DNS is fixed means PAT/`ghcr-creds` ACL.

## Related CI: Contabo Approve 403 discover

Example: [am-gateways run 36713529833](https://github.com/AM-Portfolio/am-gateways/actions/runs/36713529833) — Contabo Approve dig/preprod failed after retries with:

`HTTP 403 … failed to discover server resources, zero resources returned`

That means Contabo Argo could not list the Kind API via `kubeapi-dev.asrax.in` (tunnel/proxy blip). Fix path (proxy + ensure), then re-approve. `am-pipelines` `argo-api-lib.sh` now also retries that 403 class.

If Contabo sync succeeds but pods stay **ImagePullBackOff** with GHCR **403**:

1. Cluster secret may hold an **expired classic `ghp_` PAT** while SoT is a fine-grained `github_` token in `~/.asrax/credentials.env`. Refresh:

```bash
# from laptop with kubeconfig.prod → prod-apps
python am-infra-automation/scripts/kind-fleet/refresh-ghcr-pull-secrets.py
# Contabo SoT for TF: /data/am-state/credentials/credentials.env (must include GHCR_TOKEN)
```

2. After refresh, if some packages still **403** but others pull: fine-grained PAT lacks package/repo access for those images — expand FG token to **All repositories** + Packages read, or use a classic PAT with `read:packages`, then re-run the refresh script.
