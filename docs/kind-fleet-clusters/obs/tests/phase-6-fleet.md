# Test — Obs Phase 6 (fleet ingest)

- [x] Datasource UIDs: `prometheus`, `loki`, `tempo` on `https://grafana.asrax.in`.
- [x] Catalog boards visible (platform-overview / am-services family).
- [x] Alloy DaemonSet Ready: prod apps+infra, dr apps+infra, preprod apps, dev apps+infra.
- [x] LogQL (last 1h) has lines for `environment` ∈ {dev, preprod, prod, dr, obs} with pod/container (or docker) labels.
- [x] Obs hub self-metrics present (`environment=obs`).
- [x] Prod am-logging `LOKI_URL` contains `loki.asrax.in` (if am-logging deployed).
