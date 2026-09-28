# TF outline — Terraform-first (no surgery scripts)

Design notes for a later Execute. **Do not** terraform apply / kind delete from checkboxes here alone.

**SoT:** `terraform apply` on `kind-fleet/{prod,dr}/…` roots and modules below.  
**Refuse:** ad-hoc surgery `*.ps1` / `*.sh` or manual kubectl as the operator path for dump, sync, or platform move.

## Prod Contabo (2 Kind, 1 DB)

| Today | Target (TF change) |
|-------|--------|
| [prod/infra](../../../terraform/kind-fleet/prod/infra) creates `am-prod-infra` | Keep |
| [prod/stores](../../../terraform/kind-fleet/prod/stores) on infra kubeconfig | Keep — **one** store stack |
| [prod/platform](../../../terraform/kind-fleet/prod/platform) | Var **`co_locate_on_infra`**: `false` = legacy 3rd Kind; **`true`** = infra kubeconfig, no platform Kind, `gateway_same_cluster`, routes off. Example: `terraform.tfvars.colocate.example`. **Live migrate:** plan before apply — `true` destroys `module.cluster` Kind. |
| Keycloak module on platform | Move / keep on infra via TF; remove duplicate after soak |
| [prod/apps](../../../terraform/kind-fleet/prod/apps) `am-prod-apps` | Keep |
| Cross-cluster Traefik → platform NodePort | Retire via TF/IngressRoute once in-cluster |
| Port 6445 | Free |
| Prod → R2 dump | New/extend **TF module** → `kubernetes_cron_job` (or Job) on infra; critical DBs → `asrax-disaster` |

Separate TF **state** dirs (`…/prod/platform/` vs `…/prod/stores/`) may remain — state ≠ Kind. Reuse modules: `cluster`, `db-users`, stores, `keycloak`.

### Suggested apply order (prod delta)

```text
prod/stores (if needed) → prod/platform (providers→infra; no platform Kind)
  → keycloak/tools on infra → prod/apps → dump CronJob module
```

## DR (1 Kind)

| Target (TF) |
|--------|
| Single Kind via `modules/core/cluster` (e.g. sole `am-dr-infra` / `am-dr`) |
| Namespaces: stores + platform tools + apps |
| **TF-managed** CronJob/Job: R2 pull → restore critical DBs + platform |
| No public DR store/platform DNS records |
| GitOps: sync-wave allowlist for P0 services ([FAILOVER.md](FAILOVER.md)) |

Do not rewrite finished [dr/](../dr/) history boxes; new target documented here + phase-6.

## Nonprod (1 Kind)

| Target (TF) |
|--------|
| One Kind entrypoint; NS for stores + KC + apps |
| Compact sizing; no full Lago/Temporal/n8n |
| Preprod backup → restore into nonprod DBs **before** delete (prefer TF Job + evidence checklist) |

## Backup / sync modules

| Piece | TF approach |
|-------|------|
| Source | Contabo prod critical DBs (Keycloak/`platform`, user, subscription, market-related — phase-5) |
| Dest | R2 `asrax-disaster` (failover SoT; `asrax-db-backups` stays seed-only if used) |
| Prod dump | Module owned by `prod/stores` or `prod/infra` — CronJob in-cluster |
| DR pull | Module `r2-db-pull` owned by `dr/stores` — CronJob `am-r2-db-pull` (leveled 2026-09-26; soak restore later) |
| Not SoT | Laptop one-off dump scripts |

## Refuse until cutover Execute

- `kind delete` platform on live Contabo without soak plan
- CF DNS cutover as unplanned production change
- Deleting preprod without backup evidence in phase-4
- New surgery scripts that duplicate what TF modules should own
