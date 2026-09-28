# Obs — Phase 4 (retire interim + grown)

Index: [OBS_DEPLOY.md](../OBS_DEPLOY.md).  
Interim: [GRAFANA_FLEET_DEV.md](../GRAFANA_FLEET_DEV.md).  
Tests: [tests/phase-4.md](tests/phase-4.md).

## Prereq

Phase 3 green — bare FQDNs owned by VPS2 only.

## Implement

- [x] Disable laptop `kind-fleet/dev/obs` ownership of bare FQDNs — scaled `grafana` / `prometheus-server` / `loki` / `loki-gateway` → **0** on `kind-am-dev-platform` / `monitoring`.
- [x] Remove bare grafana/loki/prometheus Hosts from **laptop** `asrax-dev-tunnel` ingress.
- [x] Update [GRAFANA_FLEET_DEV.md](../GRAFANA_FLEET_DEV.md): interim = **retired**; SoT = VPS2 Docker hub.
- [ ] Mark Phase 11 Implement/Test boxes in [TODO.md](../TODO.md) to match `obs/` (pointer to OBS_DEPLOY).
- [x] Confirm Kind stub `terraform/kind-fleet/obs` documented as **not** SoT for Phase 11.

## Test

- [x] Laptop Kind no longer serves bare grafana/loki/prometheus/tempo (tunnel + scale-down).
- [x] VPS2 stack still healthy; Grafana/Loki/Prom/Tempo via bare FQDNs.
- [x] No product apps on VPS2.
- [x] **Phase 4 green** — obs pack grown (MCP OIDC polish optional).

## Grown

- [ ] Phase 2 retention/janitor still OK.
- [ ] Phase 3 ingest labels still present from prod/DR.
- [ ] Disk free still ≥ ~40 Gi or janitor acting.

## Stop if fail / Refuse

- Destroying laptop interim before Phase 3 green (causes bare FQDN outage).
- Starting Kind on VPS2 “to fix” cutover.
- Adding 11b platform apps onto 8 GB host.
