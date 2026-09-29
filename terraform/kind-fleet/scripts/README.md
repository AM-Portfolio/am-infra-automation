# Cross-cluster bridge + exposer CoreDNS + Kind VPS boot (central)

After Docker/Kind restart, Kind node and exposer IPs drift. Bridges Endpoints and
**apps CoreDNS hosts** must be refreshed from live Docker state — never bake `172.x`
into gitops.

**SoT:** app env uses DNS only (`TEMPORAL_HOST=temporal-rpc-<env>.asrax.in:7233`).
In-cluster resolution of store/Temporal FQDNs → `am-port-exposer` IP via CoreDNS `hosts`.

| File | Use |
|------|-----|
| `refresh-cross-cluster-bridges.{ps1,sh}` | Bridges Endpoints |
| `refresh-exposer-coredns.sh` | Apps CoreDNS hosts → exposer IP |
| `refresh-exposer-hostaliases.sh` | Compat wrapper → coredns script |
| `ensure-port-exposer.sh` | Recreate exposer if store/Temporal ports closed |
| `kind-fleet-boot.sh` | Ordered boot: ensure → bridges → CoreDNS → smoke |
| `systemd/am-refresh-bridges.*` | Timer every 2 min |
| `systemd/am-refresh-exposer-hostaliases.*` | Timer every 2 min (CoreDNS) |
| `systemd/am-kind-fleet-boot.*` | Once after VPS boot |
| `../{prod,dr,preprod}/scripts/…` | Thin wrappers (fixed env) |

```text
ENV=prod bash terraform/kind-fleet/scripts/kind-fleet-boot.sh
bash terraform/kind-fleet/prod/scripts/kind-fleet-boot.sh
```

**Post-restart order:** Kind nodes → **ensure exposer** → bridges refresh → CoreDNS hosts → smoke.

TCP stores + Temporal gRPC stay on `am-port-exposer` (Docker network-aliases for non-pod clients).
