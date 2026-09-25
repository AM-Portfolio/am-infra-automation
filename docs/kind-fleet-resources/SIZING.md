# Kind fleet resource allocation (infra + platform)

**Source of truth:** Terraform modules below. This doc is the human checklist for VPS1 (`prod`) / VPS3 (`dr`) apply. Never apply prod/DR sizes on the laptop.

| Module | Path |
|--------|------|
| Infra stores | `terraform/modules/core/store-sizing` |
| Platform apps | `terraform/modules/core/platform-sizing` |

**Prod stand-up (host + Kind + which row to take):** [`docs/kind-fleet-clusters/prod/SIZING.md`](../kind-fleet-clusters/prod/SIZING.md) — serve-first **64 GB**, take **`environment=prod`** rows from tables below.  
**Agent summary:** skill `am-kind-fleet` `reference/sizing.md`.

## Rules

- Env token ∈ `{dev, prod, dr}` (never `local` / `preprod`).
- Request ≤ limit; CPU request ≥ **50m**.
- **DR limits = prod**; **prod requests ≥ DR** (DR requests ≈ 70% of prod).
- **Default row = `dev`** (module comment + laptop `kind-fleet/dev`). **Prod = `prod` row** via `kind-fleet/prod/*` `local.env = "prod"`.
- Wrapper `local.env` must match the folder (`kind-fleet/dev|prod|dr/...`).

### Fleet host inventory

| Env | Host | vCPU | RAM | SSD |
|-----|------|------|-----|-----|
| dev (default TF row) | Laptop | 12 | 32 GB | 200 GB |
| prod (use on VPS1) | VPS1 | 8 | 64 GB | 500 GB |
| prod (optional later) | After obs offload | 6 | 36 GB | 500 GB |
| dr | VPS3 | 8 | 32 GB | 500 GB |

## When prod starts

1. Confirm **prod** rows in this file match `store-sizing` / `platform-sizing` `locals.sizes.prod`.
2. Follow [`prod/SIZING.md`](../kind-fleet-clusters/prod/SIZING.md) for Kind nodes (infra two / apps+platform one).
3. On VPS1: `kind-fleet/prod/{stores,platform}` with `environment=prod` — do **not** apply from laptop.
4. Verify: `kubectl … get pods -o custom-columns=NAME:.metadata.name,CPU_REQ:…,MEM_REQ:…`
5. Domain smoke only (`*.asrax.in`); no port-forward.

### Quick: default (dev) vs prod — stores

| Store | Default (dev) | Prod (VPS1) |
|-------|---------------|-------------|
| postgresql | 50m/500m · 256Mi/1Gi · 5Gi | **250m/1000m · 1Gi/2Gi · 16Gi** |
| mongodb | 50m/500m · 512Mi/1Gi · 5Gi | **250m/1000m · 1Gi/2Gi · 16Gi** |
| redis | 50m/200m · 256Mi/512Mi · 1Gi · max 256mb | **100m/400m · 256Mi/1Gi · 4Gi · max 768mb** |
| kafka | 50m/500m · 512Mi/1Gi · 5Gi | **200m/1000m · 1Gi/2Gi · 10Gi** |
| influxdb | 50m/500m · 512Mi/1Gi · 5Gi | **100m/500m · 1Gi/2Gi · 5Gi** |
| minio | 50m/500m · 256Mi/512Mi · 5Gi | **200m/1000m · 512Mi/2Gi · 20Gi** |
| vault | 50m/200m · 128Mi/256Mi | **100m/500m · 256Mi/512Mi** |

Platform prod examples: Keycloak **500m/1Gi→2Gi** (dev 250m/768Mi→1Gi); Lago API **500m/1Gi→4Gi** (dev 200m/512Mi→2Gi). Full matrix below.

## Infra (`store-sizing`)

| Store | env | CPU req/lim | Mem req/lim | Disk | Redis maxmemory |
|-------|-----|-------------|-------------|------|-----------------|
| postgresql | dev | 50m / 500m | 256Mi / 1Gi | 5Gi | — |
| postgresql | prod | 250m / 1000m | 1Gi / 2Gi | 16Gi | — |
| postgresql | dr | 175m / 1000m | 768Mi / 2Gi | 16Gi | — |
| mongodb | dev | 50m / 500m | 512Mi / 1Gi | 5Gi | — |
| mongodb | prod | 250m / 1000m | 1Gi / 2Gi | 16Gi | — |
| mongodb | dr | 175m / 1000m | 768Mi / 2Gi | 16Gi | — |
| redis | dev | 50m / 200m | 256Mi / 512Mi | 1Gi | 256mb |
| redis | prod | 100m / 400m | 256Mi / 1Gi | 4Gi | 768mb |
| redis | dr | 100m / 400m | 256Mi / 1Gi | 4Gi | 768mb |
| kafka | dev | 50m / 500m | 512Mi / 1Gi | 5Gi | — |
| kafka | prod | 200m / 1000m | 1Gi / 2Gi | 10Gi | — |
| kafka | dr | 140m / 1000m | 768Mi / 2Gi | 10Gi | — |
| influxdb | dev | 50m / 500m | 512Mi / 1Gi | 5Gi | — |
| influxdb | prod | 100m / 500m | 1Gi / 2Gi | 5Gi | — |
| influxdb | dr | 70m / 500m | 768Mi / 2Gi | 5Gi | — |
| minio | dev | 50m / 500m | 256Mi / 512Mi | 5Gi | — |
| minio | prod | 200m / 1000m | 512Mi / 2Gi | 20Gi | — |
| minio | dr | 140m / 1000m | 384Mi / 2Gi | 20Gi | — |
| vault | dev | 50m / 200m | 128Mi / 256Mi | — | — |
| vault | prod | 100m / 500m | 256Mi / 512Mi | — | — |
| vault | dr | 70m / 500m | 192Mi / 512Mi | — | — |

Pack history: [kind-fleet-store-resources](../kind-fleet-store-resources/PLAN.md).

---

## Platform (`platform-sizing`)

| App | Component | env | CPU req/lim | Mem req/lim |
|-----|-----------|-----|-------------|-------------|
| keycloak | main | dev | 250m / 1000m | 768Mi / 1Gi |
| keycloak | main | prod | 500m / 1000m | 1Gi / 2Gi |
| keycloak | main | dr | 350m / 1000m | 768Mi / 2Gi |
| argocd | server | dev | 50m / 500m | 128Mi / 512Mi |
| argocd | server | prod | 100m / 500m | 256Mi / 512Mi |
| argocd | server | dr | 70m / 500m | 192Mi / 512Mi |
| argocd | controller | dev | 100m / 1000m | 256Mi / 1Gi |
| argocd | controller | prod | 200m / 1000m | 512Mi / 1Gi |
| argocd | controller | dr | 140m / 1000m | 384Mi / 1Gi |
| argocd | repoServer | dev | 50m / 500m | 128Mi / 512Mi |
| argocd | repoServer | prod | 100m / 500m | 256Mi / 512Mi |
| argocd | repoServer | dr | 70m / 500m | 192Mi / 512Mi |
| temporal | server | dev | 100m / 500m | 256Mi / 1Gi |
| temporal | server | prod | 250m / 1000m | 512Mi / 2Gi |
| temporal | server | dr | 175m / 1000m | 384Mi / 2Gi |
| temporal | web | dev | 50m / 200m | 128Mi / 256Mi |
| temporal | web | prod | 100m / 500m | 256Mi / 512Mi |
| temporal | web | dr | 70m / 500m | 192Mi / 512Mi |
| lago | api | dev | 200m / 1000m | 512Mi / 2Gi |
| lago | api | prod | 500m / 2000m | 1Gi / 4Gi |
| lago | api | dr | 350m / 2000m | 768Mi / 4Gi |
| lago | front | dev | 50m / 500m | 256Mi / 1Gi |
| lago | front | prod | 200m / 1000m | 512Mi / 2Gi |
| lago | front | dr | 140m / 1000m | 384Mi / 2Gi |
| n8n | main | dev | 100m / 1000m | 512Mi / 1536Mi |
| n8n | main | prod | 250m / 1000m | 1Gi / 2Gi |
| n8n | main | dr | 175m / 1000m | 768Mi / 2Gi |
| growthbook | frontend | dev | 100m / 750m | 512Mi / 1Gi |
| growthbook | frontend | prod | 200m / 1000m | 512Mi / 2Gi |
| growthbook | frontend | dr | 140m / 1000m | 384Mi / 2Gi |
| growthbook | backend | dev | 100m / 750m | 512Mi / 1Gi |
| growthbook | backend | prod | 200m / 1000m | 512Mi / 2Gi |
| growthbook | backend | dr | 140m / 1000m | 384Mi / 2Gi |
| openproject | main | dev | 100m / 1000m | 512Mi / 2Gi |
| openproject | main | prod | 250m / 1000m | 1Gi / 2Gi |
| openproject | main | dr | 175m / 1000m | 768Mi / 2Gi |
| litellm | main | dev | 50m / 500m | 256Mi / 1Gi |
| litellm | main | prod | 200m / 1000m | 512Mi / 2Gi |
| litellm | main | dr | 140m / 1000m | 384Mi / 2Gi |
| langfuse | web | dev | 100m / 500m | 512Mi / 1Gi |
| langfuse | web | prod | 200m / 1000m | 512Mi / 2Gi |
| langfuse | web | dr | 140m / 1000m | 384Mi / 2Gi |
| langfuse | clickhouse | dev | 100m / 1000m | 512Mi / 2Gi |
| langfuse | clickhouse | prod | 250m / 1000m | 1Gi / 2Gi |
| langfuse | clickhouse | dr | 175m / 1000m | 768Mi / 2Gi |
| novu | api | dev | 50m / 500m | 128Mi / 512Mi |
| novu | api | prod | 100m / 500m | 256Mi / 512Mi |
| novu | api | dr | 70m / 500m | 192Mi / 512Mi |
| novu | worker | dev | 50m / 500m | 128Mi / 512Mi |
| novu | worker | prod | 100m / 500m | 256Mi / 512Mi |
| novu | worker | dr | 70m / 500m | 192Mi / 512Mi |
| novu | web | dev | 50m / 250m | 64Mi / 256Mi |
| novu | web | prod | 50m / 250m | 128Mi / 256Mi |
| novu | web | dr | 50m / 250m | 96Mi / 256Mi |
| novu | ws | dev | 50m / 250m | 64Mi / 256Mi |
| novu | ws | prod | 50m / 250m | 128Mi / 256Mi |
| novu | ws | dr | 50m / 250m | 96Mi / 256Mi |

**Novu** deploys on platform NS `notification` (Phase 3d). **am-notification** stays on apps cluster (Phase 4+).

## OIDC test personas (domain verify)

| Username | Roles | Vault path |
|----------|-------|------------|
| `am-admin-test` | `am-admin`, `am-ops` | `apps/data/<env>/infra/keycloak-test-users` |
| `am-user-test` | `am-user` | same |

Passwords never in git. Admin SSO to every wired G24 console; user is readonly / limited.
