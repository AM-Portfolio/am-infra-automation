# Cross-cluster bridge + exposer hostAliases + Kind VPS boot (central)

Kubernetes Endpoints only store IPs. After Docker/Kind restart, Kind node IPs drift — infra Traefik bridges and apps `hostAliases` go stale.

**SoT:** refresh from Docker DNS; never bake `172.x` into app env (`TEMPORAL_HOST=temporal-rpc-<env>.asrax.in:7233`).

| File | Use |
|------|-----|
| `refresh-cross-cluster-bridges.{ps1,sh}` | Bridges Endpoints |
| `refresh-exposer-hostaliases.sh` | Apps hostAliases → exposer IP |
| `ensure-port-exposer.sh` | Recreate exposer if store/Temporal ports closed |
| `kind-fleet-boot.sh` | Ordered boot: ensure → bridges → hostAliases → smoke |
| `systemd/am-refresh-bridges.*` | Timer every 2 min |
| `systemd/am-refresh-exposer-hostaliases.*` | Timer every 2 min |
| `systemd/am-kind-fleet-boot.*` | Once after VPS boot |
| `../{prod,dr,preprod}/scripts/…` | Thin wrappers (fixed env) |

```text
ENV=prod bash terraform/kind-fleet/scripts/kind-fleet-boot.sh
bash terraform/kind-fleet/prod/scripts/kind-fleet-boot.sh
```

**Post-restart order:** Kind nodes → **ensure exposer** → bridges refresh → hostAliases refresh → smoke / CrashLoop recover.

TCP stores + Temporal gRPC stay on `am-port-exposer` (Docker DNS aliases) — do not bake `172.x` into socat.
