# Obs — Phase 3 (CF cutover + MCP)

Index: [OBS_DEPLOY.md](../OBS_DEPLOY.md).  
Interim notes: [GRAFANA_FLEET_DEV.md](../GRAFANA_FLEET_DEV.md).  
Tests: [tests/phase-3.md](tests/phase-3.md).

## Prereq

Phase 2 **green**. **User confirm** before any bare FQDN CNAME mutate.

## Implement

- [x] User confirmed cutover window.
- [x] VPS2 tunnel healthy; Host rules for grafana/loki/prometheus/tempo → Traefik. (`asrax-obs-tunnel`)
- [x] Move CNAMEs for `grafana` / `loki` / `prometheus` / `tempo`.asrax.in from laptop tunnel → **VPS2 tunnel**.
- [ ] Grafana Keycloak login at `https://grafana.asrax.in`. *(UI up; OIDC env still optional — admin/SQLite works)*
- [ ] Re-run Grafana MCP setup (`scripts/setup-grafana-dev-mcp.ps1` or obs equivalent) — `GRAFANA_URL=https://grafana.asrax.in`.
- [ ] Spot-check Alloy / am-logging on **prod** and **dr** still push bare HTTPS.
- [ ] Republish am-obs-platform dashboards to same Grafana if needed.

## Test

- [x] `https://grafana.asrax.in` answers (health/login 200) from VPS2 Compose Grafana 11.5.2.
- [x] Loki push `https://loki.asrax.in/loki/api/v1/push` → **204**; Prom `/-/ready` path via API 200; Tempo `/ready` 200.
- [ ] MCP `list_datasources` → Prom + Loki (+ Tempo).
- [ ] LogQL shows labels from **at least prod and DR** (`environment` / `cluster`).
- [x] Push smoke to `loki.asrax.in` succeeds.
- [x] **Phase 3 green** (cutover + smoke); MCP/OIDC/Alloy spot-check follow-up.

## Grown

- [ ] Ingest still healthy after ~1h.
- [x] No dual ownership of bare FQDNs (removed from `asrax-dev-tunnel` ingress).

## Stop if fail / Refuse

- Cutover without Phase 2 green or without user confirm.
- Leaving laptop + VPS2 both answering the same Hosts long-term.
- Committing tunnel tokens / Grafana SA tokens to git.
