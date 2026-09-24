# TODO — kind-fleet-store-resources

Pack: `docs/kind-fleet-store-resources/`. Resume from the first unchecked item.

## Plan loop (no impl until Agent satisfied + user confirm)

- [x] Find existing pack / Postman collection (patch, do not duplicate) — new pack; no Postman; parent is `docs/kind-fleet-clusters/` (do not edit)
- [x] Branch on **lead** — `feature/kind-fleet-store-resources` (create only after user confirm)
- [x] World-class feature map (P0/P1/P2)
- [x] First-run / virtual value UX — N/A
- [x] Latency & consistency — N/A (scheduler Pending only)
- [x] Corner-case matrix mapped to tests
- [x] Review roles filled
- [x] PLAN.md + images/ (no images — gate fail)
- [x] `architecture.drawio` via **am-architecture-drawio**
- [x] UI preview gate evaluated; n/a — not modern-ui
- [x] Design sections filled; Open questions empty
- [x] Delivery 10/10 and Design 10/10
- [x] Scorecard overall ≥ 9.5 and all dims ≥ 9.0
- [x] Adversarial review: 0 Blocker / 0 Major
- [x] **Agent satisfied: yes**
- [x] Test Plan rows executable (`kubectl` + `terraform`)
- [x] **User reviewed** PLAN + architecture + TODO and confirmed Execute

## Per service (unit-test loop) — after user confirm only

### Service: `modules/core/store-sizing` (new)

- [x] Add module: `var.environment` in `{dev,prod,dr}` → output map of store resource objects
- [x] Validate request ≤ limit; Redis `maxmemory` ≤ 75% of memory limit
- [x] Assert prod limits == dr limits; prod requests > dr requests
- [x] `terraform validate` (and `terraform test` if we add a `*.tftest.hcl`) **verified** — 6/6 pass

### Service: store app modules (existing)

- [x] `postgresql` / `mongodb` / `redis` / `kafka` / `influxdb` / `minio` / `vault`: CPU/mem/storage vars default = **dev** row
- [x] Kafka STS gains a `resources` block (today: none)
- [x] Mongo + Influx Helm values include CPU req, CPU lim, mem req, mem lim (anti-OOM; disk 5Gi)
- [x] Redis ConfigMap `maxmemory` from `var.redis_maxmemory`
- [x] PV/PVC `storage` from `var.storage` (Vault omitted); ignore_changes so live PVs are not resized
- [x] `terraform validate` per module

### Service: `kind-fleet/{dev,prod,dr}/stores` (existing)

- [x] `module "sizing"` with `environment = local.env`
- [x] Pass sizing outputs into each store module
- [x] Folder/env guard: `dev` wrapper cannot set `environment = "prod"`
- [x] **Apply laptop `dev` only** after confirm
- [x] Do **not** terraform-resize existing immortal PVs on `am-dev-infra`

## Deploy (fast — after impl)

- [x] Slot = KIND `dev` on laptop
- [x] `terraform apply` `kind-fleet/dev/stores` only
- [x] **Prod / DR:** asked this turn; **not applied** (wait for explicit yes)

## Feature-test loop

- [x] Test Plan row 1 — store-sizing validate/test
- [x] Row 2 — minio-0 resources = dev row
- [x] Row 3 — postgresql-0 resources = dev row
- [x] Row 4 — kafka-0 has resources
- [x] Row 5 — plan does not replace PVs on laptop
- [x] Row 6 — prod vs dr limits equal
- [x] Row 7 — Mongo/Influx values include resources
- [x] Row 8 — node Allocatable > request sum
- [x] All rows pass or explicitly accepted

## Report

- [x] **Only after tests verified:** write `REPORT.md`

## Deploy (slow — after user satisfied)

- [x] Not this slice (no GitOps image tags)
- [ ] **Prod:** asked again before VPS1 apply
- [ ] **DR:** asked again before VPS3 apply

## PR

- [ ] PR only if the user asked
- [ ] `/review` then `/pr-ready`
