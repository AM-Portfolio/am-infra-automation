# kubeapi-proxy (Contabo → dig VPS Kind)

Contabo main Argo talks to dig Kind **`am-dev-apps`** on Bluehost VPS **`am-vps-dev`** (`129.121.169.241`) through Cloudflare Tunnel hostname **`kubeapi-dev.asrax.in`**.

Operator `~/.asrax/kubeconfig.dev` uses the **same** hostname (bearer token) so operator laptops can kubectl without SSH to the VPS. Host-only break-glass on the dig VPS: `kubeconfig.dev.local` (`127.0.0.1:6444`). Rebuild: `python scripts/kind-fleet/refresh-kubeconfig-dev-tunnel.py` (run against dig Kind / tunnel).

**Never** point the tunnel at `https://kubernetes.default.svc` directly. Cloudflare / TLS termination breaks Kubernetes bearer auth → Contabo Approve **401 / 500 / 403** (`failed to discover server resources`).

## Working path

```text
Contabo Argo API
  → https://kubeapi-dev.asrax.in
  → Cloudflare Tunnel (asrax-dev)
  → cloudflared on dig VPS am-dev-apps
  → http://kubeapi-proxy.infra.svc.cluster.local:80   (HTTP nginx)
  → https://kubernetes.default.svc
```

| Piece | SoT |
|-------|-----|
| Dig host | Bluehost `am-vps-dev` / `129.121.169.241` (not laptop) |
| Proxy Deployment/Service | `terraform/modules/ops/kubeapi-proxy/` |
| Dev TF | `terraform/kind-fleet/dev/apps/kubeapi-proxy.tf` |
| Tunnel origin | dig/edge `kubeapi_kind_api_origin` → proxy URL + `httpHostHeader: kubernetes.default.svc` |
| Contabo cluster secret | `cluster-am-dev-apps` server `https://kubeapi-dev.asrax.in` |
| Env landing | **dev** on dig VPS `am-dev-apps`; **preprod** on Contabo `am-vps-nonprod` (see am-gitops `DEV_ON_CONTABO.md`) |

nginx must keep long watches alive (`proxy_read_timeout 3600s`, buffering off) or Contabo returns **504**.

## Self-heal (no manual command after Kind restart)

Same idea as `am-port-exposer`:

| Healer | What | Survives Kind wipe? |
|--------|------|---------------------|
| Host Docker **`am-kubeapi-proxy-ensure`** (`--restart always`) | Waits for Kind API; keeps **CoreDNS health block** valid; restarts cloudflared if DNS was down; `kubectl apply` proxy YAML if not Ready | **Yes** |
| In-cluster **`infra/kubeapi-proxy-ensure`** | Loop: if `kubeapi-proxy` not ready → re-apply | No (wiped with cluster; host ensure restores) |

**CoreDNS tripwire:** this CoreDNS build rejects one-line `health { lameduck 5s }` (`Wrong argument count … after '}'`). That CrashLoops CoreDNS → cluster DNS dies → `cloudflared` / `kubeapi-proxy` CrashLoop → Cloudflare **530** on `kubeapi-dev.asrax.in` and `am-dev.asrax.in`. The ensure loop rewrites to a multiline `health { … }` block and rolls CoreDNS + cloudflared. Same normalize runs in `refresh-exposer-coredns.sh` and `ensure-kind-host-dns.sh` so host patches cannot reintroduce the one-liner.

Scripts:

- `terraform/kind-fleet/scripts/ensure-kubeapi-proxy.sh` — start/recreate host container
- `terraform/kind-fleet/scripts/kubeapi-proxy-ensure-loop.sh` — loop inside the container (proxy + CoreDNS health heal)
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
| **Hang** pin OK but never Healthy; Argo `am-dev-apps` **Failed**; Contabo `curl kubeapi-dev` **502** while laptop **200** | dig `cloudflared` connectors stale — `kubectl --kubeconfig ~/.asrax/kubeconfig.dev.local -n infra rollout restart deploy/cloudflared`, then `scripts/kind-fleet/ensure-kubeapi-dev.ps1` until `bearer=200` |
| **500** EOF / server version | Kind / tunnel blip — retries in `am-pipelines` `argo-api-lib.sh` |
| **500** `lookup kubeapi-dev… server misbehaving` | Contabo Kind **CoreDNS** upstream (Docker `172.18.0.1`) broken — pin `forward . 8.8.8.8 8.8.4.4` via `terraform/kind-fleet/scripts/ensure-kind-host-dns.sh` (also sets Docker `daemon.json` dns + Kind node `/etc/resolv.conf`) |
| **403** discover zero resources | Same path broken or secret token stale; fix proxy+tunnel then refresh `cluster-am-dev-apps` |
| **504** | nginx/CF watch timeout — ensure long `proxy_read_timeout` |
| **ImagePullBackOff** `…/<service>:<tag>` not found | Flat GHCR path — Contabo CI publishes `ghcr.io/am-portfolio/<git-repo>/<service>`; pin must set `image.repository` (see am-gitops `set-image-tag.yml`) |

After path is healthy, **ImagePullBackOff** on the destination is often the same Docker/Tailscale DNS failure on the Kind node (`lookup ghcr.io on 172.18.0.1:53 server misbehaving`). Run as root on the VPS:

```bash
ENV=prod bash terraform/kind-fleet/scripts/ensure-kind-host-dns.sh --restart-docker
```

That writes durable `dns: ["8.8.8.8","8.8.4.4"]` (survives Tailscale/host resolv churn), patches live Kind node resolv, and pins CoreDNS forward. Hooked from `kind-fleet-boot.sh` (without docker restart). Separate GHCR **403** after DNS is fixed means PAT/`ghcr-creds` ACL.

## Kind node NotReady (host inotify)

If a Kind docker node (`am-<env>-infra-worker`, etc.) is **NotReady** with kubelet `NodeStatusUnknown`, and `docker logs` shows systemd PID1 **`Too many open files` / `Failed to create control group inotify object`**, raise host inotify and restart **only that container** — never `kind delete`:

```bash
# Contabo / VPS root — also step 0 of kind-fleet-boot.sh
ENV=prod ASRAX_HOME=/home/am-ops/.asrax bash terraform/kind-fleet/scripts/ensure-kind-node-ready.sh
# or after boot scripts sync:
ENV=prod bash /root/am-repos/am-infra-automation/terraform/kind-fleet/scripts/kind-fleet-boot.sh
```

`ensure-kind-node-ready.sh` persists `fs.inotify.max_user_watches` / `max_user_instances` under `/etc/sysctl.d/99-kind-inotify.conf` and `docker restart`s exited/NotReady Kind node containers.

Also: `refresh-exposer-coredns.sh` patches **apps and infra** CoreDNS hosts → exposer IP. Infra Keycloak talks to `postgres.asrax.in`; without the infra hosts entry it hairpins to the public VPS IP and times out.

## Related CI: Contabo Approve 403 discover

Example: [am-gateways run 36713529833](https://github.com/AM-Portfolio/am-gateways/actions/runs/36713529833) — Contabo Approve dig/preprod failed after retries with:

`HTTP 403 … failed to discover server resources, zero resources returned`

That means Contabo Argo could not list the Kind API via `kubeapi-dev.asrax.in` (tunnel/proxy blip). Fix path (proxy + ensure), then re-approve. `am-pipelines` `argo-api-lib.sh` now also retries that 403 class.

If Contabo sync succeeds but pods stay **ImagePullBackOff** with GHCR **403**:

1. **SoT is Vault** `apps/data/prod/infra/ghcr` (`username` + `token`). In-cluster CronJob `ghcr-pull-secret-sync` (every 30m + boot via `ensure-ghcr-pull-secrets.sh`) writes `ghcr-creds` / `github-registry-secret` / `regcred` in `am-apps-prod`, `am-agents-prod`, `edge`.

```bash
# Seed / rotate token into Vault (infra context), then sync
$env:KUBECONFIG="$HOME/.asrax/kubeconfig.prod"
kubectl config use-context prod-infra
python am-infra-automation/scripts/kind-fleet/seed-vault-ghcr.py --env prod
kubectl config use-context prod-apps
bash am-infra-automation/terraform/kind-fleet/scripts/ensure-ghcr-pull-secrets.sh prod
# Or one-shot from Vault without CronJob:
# (infra) python …/refresh-ghcr-pull-secrets.py --vault
# Contabo credentials SoT for TF seed: /data/am-state/credentials/credentials.env
```

2. After sync, if packages still **403**: the PAT in Vault lacks package access — use classic `read:packages` or FG **Packages: Read** + AM-Portfolio packages, update `GHCR_TOKEN` in credentials.env, re-run `seed-vault-ghcr.py`, then `ensure-ghcr-pull-secrets.sh` (or wait for CronJob).
