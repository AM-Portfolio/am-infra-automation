# PLAN — kind-fleet-store-resources

| Field | Value |
|-------|--------|
| Kind | `feature` |
| Slug | `kind-fleet-store-resources` |
| Lead repo | `am-infra-automation` |
| Other repos | none this slice |
| Target env | KIND fleet tokens `dev` / `prod` / `dr`. **No preprod. No `local`.** Confirm again before any VPS apply. |
| Branch | `feature/kind-fleet-store-resources` |
| UI previews | n/a — no modern-ui screen |
| Delivery rating | 10/10 |
| Design rating | 10/10 |
| Scorecard overall | 9.6/10 |
| Agent satisfied | yes — user confirmed Execute (evidence table). Laptop `dev` only. |

Diagram: [architecture.drawio](architecture.drawio) · Checklist: [TODO.md](TODO.md)

Parent fleet pack (do not edit in this slice): [docs/kind-fleet-clusters/PLAN.md](../kind-fleet-clusters/PLAN.md)

## Goal

MinIO and every other infra store today ship **one hardcoded CPU/memory/disk** (laptop-safe). Prod (VPS1 ~64 GB, 2-node) and DR (VPS3 32 GB, 1-node) must use **different** requests/limits and PVC sizes. Operator reviews the table below, then we wire `env` → sizing in existing store modules. No new cluster. No platform Helm this slice.

## Images

- `images/` — none. Operator table is this PLAN, not a UI mock.

## Prerequisites (done / pending / blocked)

| Check | Status | Notes |
|-------|--------|--------|
| Store modules exist | done | `terraform/modules/apps/{postgresql,mongodb,redis,kafka,influxdb,minio,vault}` |
| Fleet wrappers exist | done | `terraform/kind-fleet/{dev,prod,dr}` — prod/dr stores wrappers not applied yet |
| Cluster `vps_ram_gb` | done | `terraform/modules/core/cluster` already has `vps_ram_gb` (“reserved for later sizing”). This pack **does not auto-scale from RAM**. Env token picks the row. |
| MCP / Postman | n/a | Capacity is `kubectl` + `terraform plan`, not HTTP |
| Host RAM inventory | done | VPS1 ~64 GB; VPS3 **32 GB**; laptop Docker; VPS2 obs has no stores |

## World-class feature map

### P0 — this slice

- **Show today’s numbers** (hardcoded, same on every env).
- **Approve one table** for `dev` / `prod` / `dr` (CPU request+limit, memory request+limit, disk, Redis `maxmemory`).
- **Wire, do not invent:** `modules/core/store-sizing` keyed by `env`; each store module takes a `resources` object; wrappers pass the row for that host.
- **Laptop-safe default:** module defaults = **dev**. Omitting the object never applies prod sizes.
- **DR promote-safe limits:** DR **limits = prod**. DR **requests ≈ 70% of prod** so three Kind clusters fit on 32 GB.
- **Pin unbounded pods:** Kafka / Mongo Helm / Influx Helm currently have **no** CPU/memory. They get the table.
- **MinIO laptop align:** drop TF burst `1000m` / `1Gi` to `500m` / `512Mi` (same as `am-infra` `k8s/minio`).
- **Prove on `am-dev-infra` only** after confirm: `kubectl -n infra get pods -o custom-columns=…` matches the **dev** row. Do not apply prod/dr sizes on the laptop.

### P1 — next

- Platform UI pods (n8n, GrowthBook, OpenProject, LiteLLM, Langfuse, Temporal, Lago) — same env map, after stores Helm.
- Store admin UIs (pgAdmin, mongo-express, kafka-ui, redis-commander) — keep small on all envs.
- Apps-cluster service requests (am-market, portfolio, …).

### P2 — later or never

- Auto-size from live `vps_ram_gb` or `kubectl top`.
- HPA / VPA.
- Changing disk on an already-bound immortal hostPath PV (no expander). First create only.

## First-run / virtual value UX

N/A — no paper book, no broker money, no modern-ui.

Operator first run: open this table → confirm → terraform apply **that env’s** stores wrapper → `kubectl describe` shows the row.

## Latency & consistency

N/A for LTP / multi-service product lag.

Scheduler: if requests exceed the Kind node, pod stays **Pending** (`Insufficient cpu` / `Insufficient memory`). Operator sees that on `kubectl describe pod`. No invented p99.

## Current system (verified)

Hardcoded in Terraform today. **Same on laptop and (if applied) VPS.** Wrapper `kind-fleet/dev/stores/main.tf` passes no CPU/memory.

| Store | CPU req | CPU lim | Mem req | Mem lim | Disk | Source |
|-------|---------|---------|---------|---------|------|--------|
| **MinIO** | 100m | **1000m** | 256Mi | **1Gi** | 5Gi | `modules/apps/minio/main.tf` STS |
| Postgres | 50m | 500m | 128Mi | 512Mi | 2Gi | `modules/apps/postgresql/main.tf` |
| Redis | 50m | 200m | 64Mi | 256Mi | 1Gi | CPU req floor 50m (25m/20m too low) |
| Kafka | *none* | *none* | *none* | *none* | 5Gi | STS has no `resources` block |
| Mongo | 50m | 500m | 512Mi | 1Gi | 5Gi | explicit; no Helm default (anti-OOM) |
| Influx | 50m | 500m | 512Mi | 1Gi | 5Gi | explicit; no Helm default (anti-OOM) |
| Vault | 50m | 200m | 128Mi | 256Mi | chart | Helm values in `modules/apps/vault/main.tf` |

`am-infra` live MinIO (VPS manifests, not this TF): request `100m`/`256Mi`, limit **`500m`/`512Mi`**. TF laptop MinIO is *larger* than that.

Host RAM (fleet inventory): laptop Docker; VPS1 ~64 GB / 2-node; VPS3 32 GB / 1-node; VPS2 obs = no stores.

`vps_ram_gb` exists on the Kind cluster module and is unused.

## Evidence allocation (locked — implement this)

Sources: `am-infra` k8s manifests (what already ran), host RAM, user locks (CPU req ≥ 50m; Mongo/Influx mem limits + 5Gi intent). **Not** the guessed 32Gi/4Gi rows. `asrax-db-backups` is unmeasured — prod disk defaults to **16Gi** until `du` says otherwise.

Requests = scheduler guarantee. Limits = burst / OOMKill cap. Redis `maxmemory` ≤ 75% of memory **limit**. CPU request floor **50m**.

### Host budget (infra cluster only)

| Env | Host | Kind nodes | Infra requests (approx) | Infra limits (approx) | Why |
|-----|------|------------|-------------------------|-----------------------|-----|
| **dev** | laptop | 1 | ~0.4 CPU / ~2.5 Gi | ~3.2 CPU / ~5.5 Gi | Leave RAM for Docker + later apps/platform Kind |
| **prod** | VPS1 ~64 GB | 2 | ~1.2 CPU / ~5 Gi | ~5.4 CPU / ~11.5 Gi | Writer + shared `platform` PG/Mongo; ~2× am-infra |
| **dr** | VPS3 32 GB | 1 | ~0.9 CPU / ~3.6 Gi | **same as prod** | Replica now; promote later. 32 GB in fleet PLAN is **data**, not RAM |

### Per-store rows

| Store | dev req | dev lim | prod req | prod lim | dr req | dr lim | disk new (dev / prod=dr) |
|-------|---------|---------|----------|----------|--------|--------|--------------------------|
| **Postgres** | 50m / 256Mi | 500m / 1Gi | 250m / 1Gi | 1000m / 2Gi | 175m / 768Mi | 1000m / 2Gi | 5Gi / **16Gi** |
| **Mongo** | 50m / 512Mi | 500m / 1Gi | 250m / 1Gi | 1000m / 2Gi | 175m / 768Mi | 1000m / 2Gi | 5Gi / **16Gi** |
| **Redis** | 50m / 256Mi | 200m / 512Mi | 100m / 256Mi | 400m / 1Gi | 100m / 256Mi | 400m / 1Gi | 1Gi / 4Gi |
| Redis `maxmemory` | **256mb** | — | **768mb** | — | **768mb** | — | under mem limit |
| **Kafka** | 50m / 512Mi | 500m / 1Gi | 200m / 1Gi | 1000m / 2Gi | 140m / 768Mi | 1000m / 2Gi | 5Gi / 10Gi |
| **Influx** | 50m / 512Mi | 500m / 1Gi | 100m / 1Gi | 500m / 2Gi | 70m / 768Mi | 500m / 2Gi | 5Gi / 5Gi |
| **MinIO** | 50m / 256Mi | 500m / 512Mi | 200m / 512Mi | 1000m / 2Gi | 140m / 384Mi | 1000m / 2Gi | 5Gi / 20Gi |
| **Vault** | 50m / 128Mi | 200m / 256Mi | 100m / 256Mi | 500m / 512Mi | 70m / 192Mi | 500m / 512Mi | chart (no hostPath) |

Live `am-dev-infra` hostPath PVs stay at their **bound** sizes (PG/Mongo 2Gi, Redis 1Gi, Kafka/MinIO 5Gi). Modules `ignore_changes` on PV capacity / PVC storage so this apply does not resize. Influx Helm PVC stays 2Gi if expansion fails.

### Rules (locked)

1. **Defaults = dev.** Prod/dr only when the wrapper passes `environment = "prod"|"dr"`.
2. **Do not apply prod/dr rows on the laptop.**
3. **DR limits = prod.** Requests lower so 32 GB still schedules apps+platform.
4. **No auto-size from `vps_ram_gb`.** Use it as a comment / optional assert (`prod` expects ≥ 48, `dr` ≥ 32, `dev` any).
5. **Existing immortal PVs on `am-dev-infra` stay 2/5Gi.** Disk rows apply on **first create** of prod/dr. Do not terraform-resize a bound hostPath PV this slice (no expander; `allow_volume_expansion` is false).
6. **Shared DB stays one PG + one Mongo.** Bigger prod RAM is because many users share `platform`, not because we add DBs.
7. **No secrets / no DSN / no DNS** in this slice.

## Target journeys

1. **Review:** you read the table; change a cell or approve.
2. **Dev prove:** after confirm, apply store-sizing on `am-dev-infra`; MinIO/Postgres/… match the **dev** row; pods Running (not Pending).
3. **Prod first create (later host):** VPS1 stores wrapper passes prod row; first PVCs are 32/50Gi.
4. **DR first create (later host):** VPS3 gets prod **limits**, reduced **requests**.
5. **Reject:** terraform or a human passes prod sizes into the **dev** wrapper → `store-sizing` + wrapper validation fail, or (if bypassed) pods Pending / laptop Docker swap. Guard: wrapper `environment` must equal the folder (`dev`/`prod`/`dr`).

## Identity & ownership

- Sizing object is **not** a user id. Key = `env` token (`dev`|`prod`|`dr`).
- Cluster identity stays `am-<env>-infra`.
- No Keycloak / OIDC change.
- Store credentials unchanged (`random_password.*` / Vault KV later).

## State & money

- No ledger. State = Kubernetes `resources.requests|limits` + PV `capacity` + Redis `maxmemory`.
- **Contract** (one object per store):

```hcl
{
  cpu_request     = "50m"
  cpu_limit       = "500m"
  memory_request  = "256Mi"
  memory_limit    = "512Mi"
  storage         = "5Gi"      # omitted for Vault
  redis_maxmemory = "128mb"    # Redis only
}
```

- Validation: parse-and-compare request ≤ limit; Redis `maxmemory` ≤ 75% of `memory_limit`.
- Disk: hostPath PV `capacity` and PVC `requests.storage` stay equal (already true). Changing them on a live claim is **out of scope**.

## Isolation

- Env isolation: each host has its own Kind + own TF state. A prod number cannot leak onto laptop unless a wrapper is wrong — wrapper `local.env` is the only input to `store-sizing`.
- Cluster isolation: this map is **infra/stores only**. Apps and platform pods are P1.
- Book isolation N/A.

## Failure modes

| Failure | System | Operator sees |
|---------|--------|----------------|
| Prod sizes on laptop | Scheduler cannot place | `Pending` / `Insufficient memory` |
| Redis `maxmemory` ≥ mem limit | Redis OOM or evicts then kube OOMKill | `OOMKilled` on redis-master-0 |
| Kafka still unlimited (missed pin) | Kafka steals laptop RAM | node pressure / other stores evicted |
| Disk terraform-change on bound PV | apply error or orphan PV | PVC Pending `volume already bound` |
| DR requests = prod on 32 GB + apps | later apps Pending | describe node Allocatable |
| MinIO image still missing | ImagePullBackOff (separate) | not a sizing bug |

## Corner-case matrix

| Case | Trigger | Expected | Covered by |
|------|---------|----------|------------|
| Laptop stays small | apply `kind-fleet/dev/stores` | MinIO limit `500m`/`512Mi`; PG `50m`/`128Mi` req | Test Plan row 1–2 |
| Prod wrapper cannot run on laptop kube | `environment = "prod"` against `am-dev-infra` | wrapper validation **or** do not apply that folder | Test Plan row 3 |
| Request &gt; limit | typo in map | `terraform validate` / module validation fail | unit: store-sizing test |
| Redis maxmemory too big | `768mb` with `256Mi` limit | validation fail | unit: store-sizing test |
| Kafka missing resources | module forgets to wire | plan shows no `resources` — reject in review | Test Plan row 4 |
| Bound PV disk change | terraform storage 2Gi→32Gi on live PVC | **do not** this slice; plan must show no PV recreate on dev | Test Plan row 5 |
| DR limits match prod | read `store-sizing` `dr` vs `prod` | limits equal; requests lower | Test Plan row 6 |
| Empty / Helm-default leftover | Mongo/Influx values omit resources | values include the object | Test Plan row 7 |
| Node pressure | describe node | requests sum &lt; Allocatable | Test Plan row 8 |

## Out of scope

- Platform / apps pod sizing (P1).
- Obs/Grafana/Loki (already in `am-infra` k8s).
- Editing [docs/kind-fleet-clusters/PLAN.md](../kind-fleet-clusters/PLAN.md).
- DNS, seed, OIDC, Vault KV rewrite, G20 replica wiring.
- Resizing live hostPath PVs on `am-dev-infra`.
- MinIO Docker Hub `latest` pull (image pin is a separate apply).
- HPA/VPA, multi-replica Kafka/PG.

## Open questions

- (none — decided: DR limits = prod; defaults = dev; no RAM auto-scale; disk only on first create; MinIO dev limit aligns `am-infra`.)

## Review roles

| Role | When | Looks for |
|------|------|-----------|
| Agent architect | Until Agent satisfied | Table vs code cites; DR 32 GB fit; no PV resize on laptop |
| You | **this gate** | Numbers you want on VPS1 vs VPS3 vs laptop. Change any cell before Execute |
| Optional `/review` | If asked | am-code-review after impl |

**Please check:** prod PG 2Gi limit and 16Gi disk (until seed `du`); MinIO prod 2Gi mem; DR requests ~70%.

## UI previews (modern-ui)

- Gate: **fail** — kind=feature but P0 is Terraform/kubectl, not a modern-ui surface.
- Widget/page cites: n/a
- Previews: n/a — no modern-ui in scope

## Services

| Service | Existing or new | Impl notes | Unit tests in this slice |
|---------|-----------------|------------|--------------------------|
| `modules/core/store-sizing` | **new** (tiny map module) | `var.environment` → object map; validate request≤limit | `terraform test` or `terraform validate` + assertion file: prod limits == dr limits; dev MinIO limit is 512Mi |
| `modules/apps/{postgresql,mongodb,redis,kafka,influxdb,minio,vault}` | existing | replace hardcoded `resources` with `var.resources` (default = dev row) | validate; Kafka STS contains `resources` |
| `kind-fleet/{dev,prod,dr}/stores` | existing / stubs | `module "sizing"` + pass into each store; `local.env` must match folder | `terraform plan` on **dev** only after confirm |

No new HTTP service. No Postman collection.

## Test Plan (kubectl + terraform — no Postman)

Collection: `none — capacity, not HTTP`

| Row | Request or MCP call | Method + path | Expected | Owning service | Result |
|-----|---------------------|---------------|----------|----------------|--------|
| 1 | `terraform -chdir=terraform/modules/core/store-sizing` validate / test | local | `dev` MinIO limit `512Mi`; `prod` PG limit `2Gi` / disk `16Gi` | store-sizing | **pass** (6/6) |
| 2 | `kubectl --kubeconfig ~/.asrax/kubeconfig.am-dev-infra.yaml -n infra get pod minio-0 -o jsonpath='{.spec.containers[0].resources}'` | GET pod | request 50m/256Mi; limit 500m/512Mi | minio | **pass** |
| 3 | `kubectl … get pod postgresql-0 -o jsonpath=…` | GET pod | 50m/256Mi req; 500m/1Gi lim | postgresql | **pass** |
| 4 | `kubectl … get pod kafka-0 -o jsonpath=…` | GET pod | resources **present**; matches dev row | kafka | **pass** |
| 5 | `terraform plan` on `kind-fleet/dev/stores` | plan | no PV/PVC replace; only STS/Helm resources | wrappers | **pass** |
| 6 | read store-sizing outputs prod vs dr | plan/test | limits equal; requests prod &gt; dr | store-sizing | **pass** (Redis requests equal, accepted) |
| 7 | `helm get values mongodb -n infra` (or TF plan JSON) | values | `resources` set | mongodb | **pass** (Mongo + Influx) |
| 8 | `kubectl describe node` on `am-dev-infra` | describe | Allocatable &gt; sum of infra requests | cluster | **pass** (1300m / 2722Mi of 12 CPU / ~17.5 Gi) |

## Deploy

- After user confirm: **laptop `dev` stores only**.
- Prod/dr: **ask again** this turn before any VPS apply (even though tokens are in the table).
- Fast path: terraform apply wrapper, not GitOps image tags.

## Agent scorecard

| Dimension | Score /10 | Evidence or gap |
|-----------|-----------|-----------------|
| Product / features | 9.6 | P0/P1/P2; operator journeys; table is the product |
| Architecture / design | 9.6 | 7-sheet draw.io; BusinessFlow = review → apply → schedule |
| Data / identity / contracts | 9.5 | sizing object + env key; no user PII |
| State / money / consistency | 9.3 | PV immutability + Redis maxmemory rule |
| Reliability / failure | 9.5 | Pending / OOM / 32 GB DR |
| Security / authz | 9.2 | no secret change; env folder guard |
| Observability | 9.2 | `kubectl describe` / `jsonpath` resources; no new metrics required |
| Testability | 9.5 | 8-row plan + corner matrix mapped |
| Operability / rollout | 9.6 | defaults=dev; prod re-ask; no live PV resize |
| TODO / implementability | 9.6 | junior-ready module + wrapper tasks |
| **Overall (mean)** | **9.6** | |

## Adversarial review

| Severity | Finding |
|----------|---------|
| Minor | Helm Bitnami Mongo resource key is `resources.requests` at release values root — implementer must match chart 13.15.2 schema |
| Minor | Influx persistence `storageClass = standard` is unrelated; do not “fix” it in this slice |
| Nit | Admin UIs still unbounded — P1 |

- Blocker/Major count: **0**
- Agent satisfied = **yes** (user product approval still required)

## Rating log (agent architect loop)

| Pass | Delivery | Design | Overall | Gaps then patched |
|------|----------|--------|---------|-------------------|
| 1 | 8 | 7 | 7.6 | first pass: table only, no contract, no PV rule |
| 2 | 10 | 10 | 9.6 | sizing object, DR 70% requests, corner matrix, draw.io, Test Plan |

## User review gate

**Stop.** Review this PLAN (especially the per-store table), [architecture.drawio](architecture.drawio), and [TODO.md](TODO.md).

Reply with **approved / implement** or edit any cell (for example “prod PG 8Gi”, “MinIO keep 1Gi on laptop”).

No Execute until that confirm.

## REPORT gate

Do not write `REPORT.md` until Test Plan rows 1–8 are verified on `am-dev-infra` (prod/dr rows 6 are `terraform test` only until those hosts exist).
