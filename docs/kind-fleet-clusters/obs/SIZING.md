# Obs sizing — VPS2 Docker hub

**Take obs config from:**

| What | Path |
|------|------|
| Host class + volumes + retention | **this file** + [OBS_VPS2_SIZING.md](../OBS_VPS2_SIZING.md) |
| Deploy index | [OBS_DEPLOY.md](../OBS_DEPLOY.md) |
| Compose | [`compose/obs/`](../../../compose/obs/) |

**Not Kind:** VPS2 obs does **not** use Kind / kube-system. Do not apply `terraform/kind-fleet/obs` Kind provider for Phase 11.

## Host class (locked)

| Class | When | vCPU | RAM | SSD |
|-------|------|------|-----|-----|
| **Current (use now)** | VPS2 obs-only hub | **4** | **8 GB** | **~200 GB** |

**Refuse** Phase 11b (Vault/OpenProject/…) on this class — need ≥16 GB ([VPS2_DEV_PLATFORM.md](../VPS2_DEV_PLATFORM.md)).

State / data: `/data/am-state/obs/` on VPS2 only.

## Runtime budget (no Kind)

| Slice | Approx |
|-------|--------|
| OS + Docker | ~0.6–0.8 GB |
| Traefik + cloudflared | ~150–250 MB |
| Usable for Grafana/Loki/Prom/Tempo | ~6.0–6.5 GB |
| Leave free / page cache | ~1 GB |

Compose `mem_limit` sum **≤ ~6.5 GB**.

## Storage — no external DB

| Component | Store | Path | Volume cap |
|-----------|-------|------|------------|
| Loki | Filesystem chunks/index | `/data/am-state/obs/loki/` | **60–70 Gi** |
| Prometheus | Local TSDB | `/data/am-state/obs/prometheus/` | **30–35 Gi** |
| Tempo | Blocks on disk | `/data/am-state/obs/tempo/` | **30–40 Gi** |
| Grafana | SQLite | `/data/am-state/obs/grafana/` | **5–10 Gi** |
| OS / images / free | — | — | **≥40–50 Gi** |

## Retention

| Signal | Keep | Notes |
|--------|------|--------|
| Prometheus | **30d** | Do not shorten under log pressure |
| Loki | **14d** + janitor every **6h** @ ≥80% full | Caches **off** |
| Tempo | **5d** | Cut to 3d first if disk pressure |

## Container resources (Compose)

| Service | CPU lim | Mem lim |
|---------|---------|---------|
| Grafana | ~0.5 | 1 Gi |
| Loki | ~1.0–1.2 | 2.0 Gi |
| Prometheus | ~0.75 | 1.2 Gi |
| Tempo | ~0.75 | 1.5 Gi |
| Traefik + cloudflared | ~0.25 | 256 Mi |
| log-janitor (burst) | ~0.2 | 128 Mi |

## If OOM or disk pressure

1. Shorten **Tempo** retention (5d → 3d).
2. Shorten **Loki** retention (14d → 7d); confirm janitor.
3. **Do not** cut Prometheus below **30d** unless its volume is full.
