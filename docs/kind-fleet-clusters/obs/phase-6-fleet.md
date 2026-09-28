# Obs — Phase 6 (fleet ingest + dashboards)

Index: [OBS_DEPLOY.md](../OBS_DEPLOY.md).  
Hub cutover: [phase-3.md](phase-3.md) · [phase-4.md](phase-4.md).  
Catalog: `am-obs-platform` `platform_ctl` (ADR-010).  
Tests: [tests/phase-6-fleet.md](tests/phase-6-fleet.md).

**Prereq:** Phase 4 green — bare FQDNs owned by VPS2 Compose hub only.

## Locked

| Item | Value |
|------|--------|
| Hub | VPS2 Compose — `https://grafana.asrax.in` |
| Pod logs | **Alloy DaemonSets** on each fleet apps (+ infra) cluster |
| App telemetry | **am-logging** → bare `LOKI_URL` (does **not** replace Alloy) |
| Push URLs | `https://loki.asrax.in/loki/api/v1/push` · `https://prometheus.asrax.in/api/v1/write` |
| Labels | `environment`, `cluster` |
| Datasource UIDs | `prometheus`, `loki`, `tempo` (am-obs bindings) |

| Env | Alloy target |
|-----|----------------|
| **dev** | Fix / keep `kind-fleet/dev/{apps,infra}` → bare HTTPS |
| **preprod** | Alloy on Contabo apps (+ infra if present) |
| **prod** | Alloy on `am-prod-apps` + `am-prod-infra` |
| **dr** | Alloy on `am-dr-apps` + `am-dr-infra` |
| **obs** | Compose Alloy + scrapes on VPS2; `environment=obs` |

## Implement

### 6A — Grafana datasources + republish

- [x] Provisioning UIDs `prometheus` / `loki` / `tempo` in `compose/obs/grafana/provisioning/datasources/datasources.yml`.
- [x] Recreate Grafana on VPS2 so provisioning applies.
- [x] Create folders if needed: `am-platform` / `am-technical` / `am-product` / `am-support`.
- [x] `platform_ctl generate --target dev-fleet` then `AM_OBS_ALLOW_LEGACY_PUBLISH=1 platform_ctl apply --target dev-fleet --unit artifacts --apply`.
- [x] Re-run `scripts/setup-grafana-dev-mcp.ps1` (or SA token) for MCP.

### 6B — Obs hub self-telemetry

- [x] Compose Alloy (mem ≤256Mi) on VPS2: Docker logs → local Loki; labels `environment=obs`, `cluster=am-obs`.
- [x] Scrape Grafana / Loki / Prom / Tempo / Traefik (+ cadvisor) into local Prometheus.
- [x] Platform overview / hub health panels have series for obs.

### 6C — Alloy on prod / dr / preprod (+ fix dev)

- [x] `terraform/kind-fleet/prod/{apps,infra}/alloy.tf` → bare HTTPS; apply on VPS1.
- [x] `terraform/kind-fleet/dr/{apps,infra}/alloy.tf` → bare HTTPS; apply on VPS3.
- [x] `terraform/kind-fleet/preprod/apps/alloy.tf` (+ infra if cluster) → Contabo; apply.
- [x] Dev Alloy still/again pushes bare HTTPS (not dead ClusterIP interim Loki).
- [x] DaemonSets Ready; covers **am-apps-*** and **am-agents-*** on apps clusters.

### 6D — Prod am-logging LOKI_URL (secondary)

- [x] Add `prod/values-overlays/obs-hub.yaml` (or `extra-am-logging.yaml`) with bare `LOKI_URL`.
- [x] Wire AppSet / overlay; Argo sync `am-logging-prod`. *(live `kubectl set env` applied; **commit+push am-gitops** so AppSet self-heal keeps it)*

## Test

- [x] MCP / UI: datasources UIDs `prometheus` + `loki` (+ `tempo`).
- [x] Search shows platform-overview / tech-am-services (or equivalent catalog boards).
- [x] LogQL last 1h: Alloy lines for `environment` in **dev**, **preprod**, **prod**, **dr**, **obs** (pod/container labels — not am-logging alone).
- [x] Prom: remote_write or scrapes present for those envs / obs hub.
- [x] **Phase 6 green**.

## Grown

- [ ] Phase 2 retention/janitor still OK on VPS2.
- [ ] Alloy DaemonSets still Ready after node reboot (prod/dr).
- [ ] Dashboards still resolve datasource UIDs after Grafana recreate.

## Stop if fail / Refuse

- Relying on am-logging alone for agents/infra visibility.
- Skipping preprod Alloy.
- Kind on VPS2; secrets in git.
- Skipping this doc file as SoT (mark boxes here).
