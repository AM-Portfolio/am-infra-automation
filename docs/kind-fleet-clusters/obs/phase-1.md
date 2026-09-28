# Obs — Phase 1 (Docker layout)

Index: [OBS_DEPLOY.md](../OBS_DEPLOY.md) · Sizing: [SIZING.md](SIZING.md).  
Compose SoT: [`compose/obs/`](../../../compose/obs/).  
Tests: [tests/phase-1.md](tests/phase-1.md).

## Prereq

Phase 5.2 green. Host **4c / 8 GB / ~200 GB**.

## Implement

- [x] Confirm Docker Engine running on VPS2; Compose v2 available.
- [x] Confirm **`kind get clusters`** empty / no `am-obs` Kind name.
- [x] Create dirs (owned by `am-ops`):
  - `/data/am-state/obs/loki`
  - `/data/am-state/obs/prometheus`
  - `/data/am-state/obs/tempo`
  - `/data/am-state/obs/grafana`
  - `/data/am-state/obs/compose` (or symlink to repo checkout)
- [x] Sync [`compose/obs/`](../../../compose/obs/) onto VPS2 under `/data/am-state/obs/compose/`.
- [x] Create Docker network `am-obs` (private; no public publish of backends).
- [ ] Place secrets only under `/data/am-state/obs/secrets/` (gitignored / never commit) — Grafana OIDC client secret, tunnel token file.

## Test

- [x] Dirs exist; writable by `am-ops`.
- [x] `docker network inspect am-obs` OK.
- [x] No Kind clusters.
- [x] Disk free ≥ **40 Gi** before stack start.
- [x] **Phase 1 green** (secrets for tunnel/OIDC still pending phase-3).

## Grown

- [ ] Dirs still present after Docker restart.
- [ ] No accidental `0.0.0.0` publish of Loki/Prom ports.

## Stop if fail / Refuse

- Kind create / `terraform/kind-fleet/obs` Kind apply.
- External Postgres/Mongo for Grafana or Loki.
- Product namespaces or `am-apps-*`.
