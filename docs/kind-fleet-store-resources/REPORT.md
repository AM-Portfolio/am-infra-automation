# REPORT — kind-fleet-store-resources

Write this file **only after** per-service unit tests are verified and the Test Plan (Postman or MCP) is verified. Do not use it as a success doc while rows are fail or not verified.

| Field | Value |
|-------|--------|
| Kind | `feature` |
| Env | KIND laptop `dev` (`am-dev-infra`) only |
| Delivery rating at impl start | 10/10 |
| Design rating at impl start | 10/10 |
| Scorecard overall at impl start | 9.6 |
| Agent satisfied at impl start | yes |

## Prerequisites

| Check | Outcome |
|-------|---------|
| MCP | n/a — capacity is `kubectl` + `terraform`, not HTTP |
| APIs | n/a |
| Postman | none existed; none created |

## Per-service unit tests

| Service | `am test` | Notes |
|---------|-----------|--------|
| `modules/core/store-sizing` | verified | `terraform validate` + `terraform test`: 6/6 pass (dev MinIO 512Mi, prod PG 2Gi/16Gi, DR limits = prod) |
| `modules/apps/{postgresql,mongodb,redis,kafka,influxdb,minio,vault}` | verified | `terraform validate` each module: valid |
| `kind-fleet/dev/stores` | verified | wrapper `terraform validate` valid; laptop apply already on cluster |
| `kind-fleet/{prod,dr}/stores` | verified | sizing stubs + folder guards validate; **not applied** |

## Feature Test Plan

| Row | kubectl / terraform | Result |
|-----|---------------------|--------|
| 1 | `terraform validate` + `terraform test` in `store-sizing` | **pass** — 6/6 |
| 2 | `minio-0` resources | **pass** — req 50m/256Mi, lim 500m/512Mi |
| 3 | `postgresql-0` resources | **pass** — req 50m/256Mi, lim 500m/1Gi |
| 4 | `kafka-0` resources | **pass** — req 50m/512Mi, lim 500m/1Gi |
| 5 | `terraform plan` `kind-fleet/dev/stores` | **pass** — 0 add, 0 destroy; no PV/PVC replace. Immortal PVs still 2/2/1/5/5 Gi |
| 6 | prod vs dr limits | **pass** — limits equal on every store. Requests prod ≥ dr; Redis requests are **equal** (100m/256Mi) as locked in PLAN |
| 7 | Helm values include `resources` | **pass** — Mongo and Influx user values both set CPU/mem req+lim |
| 8 | node Allocatable > request sum | **pass** — Allocatable 12 CPU / ~17.5 Gi; allocated requests 1300m (10%) / 2722Mi (15%) |

Also live and matching the **dev** row: Redis 50m/256Mi → 200m/512Mi (`maxmemory 256mb`); Mongo 50m/512Mi → 500m/1Gi; Influx 50m/512Mi → 500m/1Gi; Vault 50m/128Mi → 200m/256Mi. All store pods Running.

## Deploy

| Step | Env | Command | Result |
|------|-----|---------|--------|
| Fast apply | laptop `dev` only | `terraform apply` `kind-fleet/dev/stores` (Influx Helm values targeted to persist resources; PVC size left at 2Gi) | pass |
| Prod approval | VPS1 | asked this turn; **not applied** | n/a until you say yes |
| DR approval | VPS3 | asked this turn; **not applied** | n/a until you say yes |
| Slow Actions | | not this slice | n/a |
| GitOps image-tags | | not this slice | n/a |

Notes: slot is KIND `am-dev-infra` on the laptop. Kind `standard` StorageClass has `allowVolumeExpansion=false`, so the live Influx Helm PVC stayed **2Gi** (accepted). Immortal hostPath PVs were not resized.

## Remaining gaps

- `kind-fleet/{prod,dr}/stores` are **sizing stubs** (env guard + `store-sizing` outputs). Full store modules are copied from `dev` on first VPS create — parent pack `kind-fleet-clusters`.
- Laptop Influx disk stays 2Gi until a new cluster first-creates at 5Gi.
- Admin UIs (pgAdmin, kafka-ui, mongo-express, redis-commander) still unbounded — PLAN P1.
- Platform / apps pod sizing — see [`docs/kind-fleet-resources/SIZING.md`](../kind-fleet-resources/SIZING.md) + `modules/core/platform-sizing`.
- `terraform plan` on the laptop wrapper still shows in-place Helm metadata / secret attribute noise. Do not apply that on a whim; it is not a PV resize.
- No PR (you did not ask).

## PR

Not opened. Say if you want `/review` then `/pr-ready`.
