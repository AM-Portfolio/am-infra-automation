# RETIRED — Helm Grafana/Loki/Prometheus for Contabo / preprod

**Do not `terraform apply` this directory** for kind-fleet Contabo or preprod Kind.

Fleet observability SoT is **VPS2 Docker Compose** (`compose/obs/`) — one Grafana at `grafana.asrax.in`. Env Alloy modules under `terraform/kind-fleet/*/apps/alloy.tf` ship into that hub.

Applying this stack would recreate an in-cluster Grafana and store PVCs (disk waste + dual UI). Kept in git only as historical reference.
