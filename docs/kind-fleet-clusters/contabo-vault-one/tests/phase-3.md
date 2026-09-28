# Phase 3 tests — One Kind lean preprod (CSI + AppSets + drain Contabo dig)

**Phase:** [../phase-3.md](../phase-3.md)

## Test cases

### Inventory + Vault

| ID | Case | Pass criteria |
|----|------|---------------|
| T3.1 | Nonprod inventory | Kind/NS/Argo list recorded; keep vs remove marked in INVENTORY |
| T3.2 | Preprod KV present | Contabo `apps/data/preprod` has infra + services + shared (38 leaves); hosts `*.asrax.in` |
| T3.3 | No prod Vault writes | Plan/apply (if any) never writes `apps/data/prod` |
| T3.4 | JWT CSI | Overlay → `vault.asrax.in` + JWT role for preprod SA; `audience: vault`; no TokenReview to Kind API |

### Preprod apps (Contabo Argo — prod-fleet shape)

| ID | Case | Pass criteria |
|----|------|---------------|
| T3.5 | Apps AppSet enrolled | Contabo Argo ApplicationSet for **preprod apps** → `am-vps-nonprod` / `am-apps-preprod` |
| T3.6 | Apps Synced/Healthy | Enrolled `*-preprod` app Applications Synced + Healthy |
| T3.7 | Apps pods Ready | Deployments Available/Ready in `am-apps-preprod`; CSI mounts OK |

### Preprod agents (Contabo Argo — prod-fleet shape)

| ID | Case | Pass criteria |
|----|------|---------------|
| T3.8 | Agents AppSet enrolled | Contabo Argo ApplicationSet for **preprod agents** → `am-agents-preprod` |
| T3.9 | Agents Synced/Healthy | Enrolled agents Synced + Healthy (excl. n8n/platform/kafka-only) |
| T3.10 | Agents pods Ready | Deployments Ready in `am-agents-preprod`; CSI OK |

### Edge + Contabo dig drain + safety

| ID | Case | Pass criteria |
|----|------|---------------|
| T3.11 | Edge minimal | Only Traefik + cloudflared in edge NS; IngressRoutes via that Traefik |
| T3.12 | Contabo dig drained | No Contabo Argo Apps targeting Contabo `am-apps-dev` / `am-agents-dev`; NS deleted only after user confirm |
| T3.13 | Rollback path | vault-preprod still available until Phase 5 |
| T3.14 | Laptop dig unchanged | Laptop `am-dev-apps` / local Argo not modified by this phase |
| T3.15 | Prod Kind untouched | No Contabo prod Kind / prod AppSet / `apps/data/prod` changes |
| T3.16 | No surgery | Deploy path Contabo Argo / `am gitops` only |

## Grown

- [ ] T3.* pass when executed

## Evidence

Inventory table; Contabo Argo Health; pod Ready counts; overlay snippet (addr + authPath only); dig drain confirm note.
