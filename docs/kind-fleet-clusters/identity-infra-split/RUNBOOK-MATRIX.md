# TF → host → Kind → NS matrix (identity-infra-split)

Operator answer sheet. Update when Kind counts change. No secrets.

## Contabo prod (VPS1) — live 2026-09-26

| TF root | Host path (state) | Kind | Port | Main NS |
|---------|-------------------|------|------|---------|
| `terraform/kind-fleet/prod/infra` | `/data/am-state/terraform/prod/infra/` | `am-prod-infra` | 6443 | `infra`, `vault`, `monitoring` |
| `terraform/kind-fleet/prod/stores` | `/data/am-state/terraform/prod/stores/` | → infra kubeconfig | — | `infra` stores + **R2 dump CronJob** |
| `terraform/kind-fleet/prod/platform` | `/data/am-state/terraform/prod/platform/` | → infra (`co_locate_on_infra=true`) | — | `identity`, `argocd`, `temporal`, `billing`, `n8n`, … |
| `terraform/kind-fleet/prod/apps` | `/data/am-state/terraform/prod/apps/` | `am-prod-apps` | 6444 | `am-apps-prod`, `am-agents-prod`, `edge` |

**Retired:** `am-prod-platform` :6445.

**Kubeconfig:** `/data/am-state/kubeconfig.am-prod-{infra,apps}.yaml` · laptop `~/.asrax/` + `~/.kube` contexts `kind-am-prod-*`.

**R2 dump:** CronJob `am-r2-db-dump` · schedule `0 */6 * * *` · bucket `asrax-disaster` · prefix `prod/<stamp>/` + `prod/latest/`.

## DR (VPS3) — live today vs target

| | Live today | Target (Phase 6) |
|--|------------|------------------|
| Kind | `am-dr-infra` :6443 · `am-dr-apps` :6444 · `am-dr-platform` :6445 | **1** Kind (stores + platform NS + apps) |
| TF | `kind-fleet/dr/{infra,stores,platform,apps,…}` | Same roots; colocate/collapse via TF (no surgery) |
| R2 pull | CronJob `am-r2-db-pull` `30 */6 * * *` (TF `dr/stores`) | Same; soak full restore later |
| Public DNS | No `*-dr` store/platform | Keep refused |
| Platform Kind | `am-dr-platform` :6445 live | `co_locate_on_infra=true` → infra (TF ready, not applied) |

**Kubeconfig:** `/data/am-state/kubeconfig.am-dr-{infra,apps,platform}.yaml`.

**R2 pull:** image `am-r2-db-pull:local` (VPS3 containerd-snapshotter → load via Contabo `docker save` tar + `kind load image-archive`).

## Nonprod / VPS2 + laptop lab

| | Live | Target (Phase 4) |
|--|------|------------------|
| Host VPS2 | Compose obs only (~8 GB) | **1** Kind lean when RAM ≥16 GB |
| Laptop lab | `am-dev-infra` / `apps` / `platform` (3 Kind) | Colocate platform → infra via `dev/platform` `co_locate_on_infra` |
| TF | `kind-fleet/dev/*` · `kind-fleet/obs` | One Kind entrypoint; Vault `apps/data/dev/` |
| Contabo stores | Must not use | Isolation required |

## Apply order (delta)

```text
Contabo: stores → platform (colocate) → apps → r2 dump
DR:      stores (pull CronJob) → collapse to 1 Kind (separate Execute) → CF cutover only when approved
```
