# Phase 0 inventory (filled from repo — 2026-09-26)

No cluster mutations. Target: Contabo **2** Kind / **1** DB; DR **1**; nonprod **1**. Terraform-first.

## Stores (`terraform/kind-fleet/prod/stores`)

| Module | Role |
|--------|------|
| postgresql | One Contabo PG stack |
| mongodb | Mongo |
| redis | Redis |
| kafka | Kafka |
| influxdb | Influx |
| minio | MinIO |
| vault | One Vault |
| db_users | platform DB + lago + app users/schemas |

**Confirm:** single store stack shared by platform tools + apps.

## Platform (`terraform/kind-fleet/prod/platform`)

| Module | Status |
|--------|--------|
| `module.cluster` (platform Kind :6445) | **GONE** — `co_locate_on_infra=true` applied 2026-09-26 |
| keycloak | **On infra** (`identity` NS) |
| argocd, temporal, lago, n8n, growthbook, openproject, litellm, langfuse, novu | **On infra** NS |
| `route_*` cross-cluster-http | **OFF** (`gateway_same_cluster=true`) |
| apps_traefik_bridge | Keep (infra → apps :30080) |

## Kind ports (live 2026-09-26)

| Cluster | Port | Status |
|---------|------|--------|
| am-prod-infra | 6443 | Live |
| am-prod-apps | 6444 | Live |
| ~~am-prod-platform~~ | ~~6445~~ | **Retired** (connection refused) |

## Vault paths

| Path | Use |
|------|-----|
| `apps/data/prod/…` | Contabo prod |
| `apps/data/preprod/…` / `dev/…` | Nonprod (same Vault) |

## Auth bridge (live)

In-cluster on infra (`gateway_same_cluster=true`): `auth.asrax.in` → Keycloak Service. Cross-cluster NodePort bridge retired with platform Kind.

## R2

| Bucket | Role |
|--------|------|
| `asrax-disaster` | Failover SoT (prod dump → DR pull) |
| `asrax-db-backups` | Seed (separate) |

## Hosts / kubeconfig / TF state

| Host | Kind target | Kubeconfig | TF state |
|------|-------------|------------|----------|
| Contabo VPS1 | infra + apps (**2** Kind live) | `/data/am-state/kubeconfig.am-prod-{infra,apps}.yaml` · laptop `~/.asrax/` + `~/.kube` contexts | `/data/am-state/terraform/prod/` |
| DR VPS3 | **1** Kind target (today still 3 Kind: infra/apps/platform) | (delta) | `/data/am-state/terraform/dr/` |
| Nonprod / VPS2 | **1** Kind lean target; today **Compose obs only** (~8 GB — no Kind yet) | from `VPS/.env` | TBD / `kind-fleet/dev/` |
| Preprod legacy | **Already deleted** (fleet TODO Phase C: `kind delete am-preprod`) — no live dump source | — | Vault key-names only under `apps/data/preprod/…` |

## Grown

- [x] Inventory from TF sources
- [x] Live Traefik / auth confirm (OIDC 200; platform-on-infra)
- [x] Preprod: no live cluster — Phase 4 backup gate = N/A (document only); nonprod = new lean Kind, not restore-from-preprod PVC
