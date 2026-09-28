# Obs — Phase 2 (Compose stack)

Index: [OBS_DEPLOY.md](../OBS_DEPLOY.md) · Sizing: [SIZING.md](SIZING.md).  
Compose: [`compose/obs/`](../../../compose/obs/).  
Tests: [tests/phase-2.md](tests/phase-2.md).

```text
2A Traefik + cloudflared → 2B Loki/Prom/Tempo/Grafana → 2C janitor → 2D health (pre-DNS)
```

## Prereq

Phase 1 green. Access off for human Grafana until OIDC wired (Keycloak redirect `https://grafana.asrax.in/*`).

## Implement

### 2A — Edge

- [x] Start Traefik on Docker network `am-obs` (HTTP entrypoint for tunnel origin).
- [x] Start cloudflared with tunnel token from `/data/am-state/obs/secrets/` — origin **only** Traefik. *(profile `tunnel` · `cloudflared.env`)*
- [x] Host routers for `grafana` / `loki` / `prometheus` / `tempo`.asrax.in → backends.
- [x] **No** `-p 3100:3100` (etc.) on public NIC — backends bind Docker network only.

### 2B — Backends (no external DB)

- [x] Loki: filesystem store → `/data/am-state/obs/loki/`; retention **14d**; caches **off**; mem ≤ **2 Gi**.
- [x] Prometheus: TSDB → `/data/am-state/obs/prometheus/`; retention **30d**; mem ≤ **1.2 Gi**.
- [x] Tempo: blocks → `/data/am-state/obs/tempo/`; retention **5d**; mem ≤ **1.5 Gi**.
- [x] Grafana: SQLite → `/data/am-state/obs/grafana/`; mem ≤ **1 Gi**; datasources → Loki/Prom/Tempo on Docker DNS. *(OIDC env pending secrets)*
- [x] Compose mem limits sum ≤ **~6.5 GB**.

### 2C — Janitor

- [x] log-janitor every **6h**: if Loki volume ≥ **80%** (or always), clean older than retention.
- [x] Never shorten Prometheus 30d from janitor.

### 2D — Pre-cutover health

- [x] All containers healthy (`docker compose ps`) — except cloudflared until token.
- [x] From another host: public IP ports for 3100/9090/3200/3000 **closed**.
- [ ] Tunnel Host match works (temporary verify via CF or curl through tunnel) **before** stealing CNAMEs from laptop.

## Test

- [x] Containers up; Traefik routes resolve on Docker network.
- [x] Loki ready; Prometheus ready; Grafana health OK.
- [ ] Grafana UI reachable via tunnel Host (even if DNS still points at interim).
- [x] Disk usage within [SIZING.md](SIZING.md) caps.
- [x] **Phase 2 green** for backends (tunnel profile pending).

## Grown

- [ ] Stack survives Docker daemon restart (restart policies).
- [ ] Janitor logged at least one successful run or dry-run.

## Stop if fail / Refuse

- CF CNAME cutover before this gate green.
- Kind / external DB.
- Publishing backends on `0.0.0.0`.
