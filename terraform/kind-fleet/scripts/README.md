# Cross-cluster bridge refresh (central)

Kubernetes Endpoints only store IPs. After Docker/Kind restart, Kind node IPs on the docker network drift — infra Traefik bridges (`*-platform`, `apps-traefik-bridge`) go stale.

**SoT:** refresh from Docker DNS via label `am.io/backend-host` (set by `cross-cluster-http` / `apps-traefik-bridge` modules).

| File | Use |
|------|-----|
| `refresh-cross-cluster-bridges.ps1` | Laptop / Windows / warmup |
| `refresh-cross-cluster-bridges.sh` | Contabo / Linux / systemd |
| `systemd/am-refresh-bridges.{service,timer}` | Auto every 2 min on Contabo |
| `../{dev,prod,dr,preprod}/scripts/…` | Thin wrappers (fixed env) |

```text
# one-shot
powershell -File terraform/kind-fleet/scripts/refresh-cross-cluster-bridges.ps1 -Env prod
ENV=prod bash terraform/kind-fleet/scripts/refresh-cross-cluster-bridges.sh

# or env wrapper
bash terraform/kind-fleet/prod/scripts/refresh-cross-cluster-bridges.sh
```

**Post-restart order:** exposer (Docker DNS) → Vault unseal → **this refresh** → warmup / restart CrashLoop pods.

TCP stores stay on `am-port-exposer` (also Docker DNS) — do not bake `172.x` into socat.
