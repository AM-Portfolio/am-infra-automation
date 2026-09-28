# OBS deploy — shared observability hub on VPS2

**Checkbox SoT for obs:** [`obs/`](obs/) (unchecked until executed).  
**Historical multi-env pack:** [TODO.md](TODO.md) Phase 11 (do not wipe; prefer marking boxes in `obs/`).  
**Prod / DR tracks:** [PROD_DEPLOY.md](PROD_DEPLOY.md) · [DR_DEPLOY.md](DR_DEPLOY.md).

Docs + Compose scaffolding first. No Cloudflare CNAME cutover until you confirm after stack health green on VPS2.

## Locked

| Item | Value |
|------|--------|
| Host | VPS2 (`VPS_2_IP` from `VPS/.env`) |
| Env token | `obs` |
| Hardware | **4 vCPU · 8 GB RAM · ~200 GB SSD** — [obs/SIZING.md](obs/SIZING.md) · [OBS_VPS2_SIZING.md](OBS_VPS2_SIZING.md) |
| Runtime | **Docker Compose only — no Kind** |
| Data dirs | `/data/am-state/obs/{loki,prometheus,tempo,grafana}/` on **VPS2 only** |
| Compose SoT | [`compose/obs/`](../../compose/obs/) in this repo; run on VPS2 as `am-ops` |
| Day-2 | `am-ops` / `am-vps2-ops` · destructive Docker/cloudflared = G1 |
| External DB | **None** — no Postgres/Mongo/MinIO for Grafana or Loki |
| Log store | Loki filesystem chunks under `/data/am-state/obs/loki/` |
| Grafana store | Embedded SQLite under `/data/am-state/obs/grafana/` (UI/config only) |
| Edge | Traefik + cloudflared — tunnel → Traefik **only** |
| Stack | Grafana + Loki + Prometheus + Tempo + log-janitor |
| FQDNs | Bare `grafana` / `loki` / `prometheus` / `tempo`.asrax.in |
| Ingest | **All envs** push here; label `environment` / `cluster` |
| Product | **No** `am-apps-*` / agents / kagent / Kind on VPS2 |
| 11b | **Out of scope** on this 8 GB box — [VPS2_DEV_PLATFORM.md](VPS2_DEV_PLATFORM.md) later (≥16 GB) |
| Interim | Laptop `kind-fleet/dev/obs` — retire after phase-3 cutover green |

## Sequence (obs)

```text
P → 0 → C (inventory VPS2)
  → 5.2 am-ops (already largely green)
  → 1 Docker layout + data dirs
  → 2 Compose: Traefik + tunnel + Grafana/Loki/Prom/Tempo + janitor
  → 3 CF bare FQDN cutover + MCP  [confirm before CNAME mutate]
  → 4 Retire laptop kind-fleet/dev/obs interim + grown
  → 6 Fleet ingest: datasource UIDs + platform_ctl republish + Alloy all envs + obs self-telemetry
```

| Order | Phase | File |
|-------|-------|------|
| 1 | P / 0 / C | [obs/phase-p-0-c.md](obs/phase-p-0-c.md) |
| 2 | 5.2 VPS security | [obs/phase-5.md](obs/phase-5.md) |
| 3 | 1 Docker layout | [obs/phase-1.md](obs/phase-1.md) |
| 4 | 2 Compose stack | [obs/phase-2.md](obs/phase-2.md) |
| 5 | 3 CF cutover | [obs/phase-3.md](obs/phase-3.md) |
| 6 | 4 Retire interim | [obs/phase-4.md](obs/phase-4.md) |
| 7 | **6 Fleet ingest** | [obs/phase-6-fleet.md](obs/phase-6-fleet.md) |

Detail: [obs/README.md](obs/README.md) · [obs/SIZING.md](obs/SIZING.md).

## Storage (no external DB)

| Component | External DB? | Path on VPS2 |
|-----------|--------------|--------------|
| Loki (logs) | No — filesystem chunks/index | `/data/am-state/obs/loki/` |
| Grafana | No — SQLite | `/data/am-state/obs/grafana/` |
| Prometheus | No — local TSDB | `/data/am-state/obs/prometheus/` |
| Tempo | No — blocks on disk | `/data/am-state/obs/tempo/` |

Grafana **queries** Loki/Prom/Tempo; it does **not** store fleet logs.

## Not in this pack (pointers)

- Phase **11b** platform hub (Vault `apps/data/dev`, OpenProject/Lago/…) — [VPS2_DEV_PLATFORM.md](VPS2_DEV_PLATFORM.md) (needs ≥16 GB)
- Prod/DR Kind fleets — [PROD_DEPLOY.md](PROD_DEPLOY.md) / [DR_DEPLOY.md](DR_DEPLOY.md)
- Interim laptop Grafana notes — [GRAFANA_FLEET_DEV.md](GRAFANA_FLEET_DEV.md)

## Refuse

- Kind / `am-obs` Kubernetes cluster on VPS2 for this pack
- External DB (Postgres/Mongo/MinIO) for Grafana or Loki on this box
- Publishing Loki/Prom/Tempo/Grafana ports on the public NIC (`0.0.0.0`)
- Dual tunnel ownership of bare grafana/loki/prometheus/tempo FQDNs
- Product apps / Argo product waves on VPS2
- Phase 11b colocation on **8 GB**
- CF CNAME mutate before phase-2 health green + **user confirm**
- Commit passwords / tokens from `VPS/.env`
- Disposable `obs-phase*.sh` surgery scripts — fix Compose/docs, re-apply

## Operator loop

```text
Prereq → Implement → mcp-sync (when needed) → Test → Grown → next
```

Fail → stay on phase. Mark boxes in [`obs/`](obs/) (not only laptop TODO.md).
