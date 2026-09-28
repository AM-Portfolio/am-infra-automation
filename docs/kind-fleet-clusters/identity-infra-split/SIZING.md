# Identity-infra-split — sizing

**Prod Contabo tables:** reuse [prod/SIZING.md](../prod/SIZING.md) + [`docs/kind-fleet-resources/SIZING.md`](../../kind-fleet-resources/SIZING.md) with `environment=prod`.

## Contabo prod — 2 Kind, 1 DB stack

| Class | vCPU | RAM | SSD | Notes |
|-------|------|-----|-----|-------|
| Current | **8** | **64 GB** | **500 GB** | Serve first |
| After platform-on-infra | same | same | same | Tools share infra RAM with stores; apps Kind separate |

| Cluster | Port | Role |
|---------|------|------|
| `am-prod-infra` | 6443 | **One** store stack + Keycloak + Vault + Traefik + platform NS (Argo/Temporal/Lago/…) |
| `am-prod-apps` | 6444 | Product pods + am-identity |
| ~~`am-prod-platform`~~ | ~~6445~~ | **Retired** |

Headroom: RAM free **≥16 GiB**, disk **&lt;70%**, CPU sustained **&lt;70%**.

Store sizes: **prod** row in kind-fleet-resources. Lago DB `lago` on the **same** infra PG.

## DR VPS — 1 Kind

| Guidance | |
|----------|--|
| Hardware | See [dr/SIZING.md](../dr/SIZING.md) as floor; single Kind holds DBs + platform NS + services |
| Data | Warm via R2 auto-sync (not a second public DB DNS) |
| Cold start | Allowlist services first — see [FAILOVER.md](FAILOVER.md) |

## Nonprod — 1 Kind lean

| Guidance | |
|----------|--|
| Hardware | Other VPS from `VPS/.env` — not Contabo |
| Stores | Same engine list, compact/`dev` sizing |
| Platform | No full Temporal/Lago/n8n |
| Apps | preprod/dev only |

## Refuse

- Second Contabo store STS “for platform”
- Full prod request tables on undersized DR without allowlist
- Putting nonprod STS on Contabo
