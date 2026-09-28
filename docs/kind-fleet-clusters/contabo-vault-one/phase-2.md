# Phase 2 — Contabo Vault seed + Dev apps/agents via Contabo Argo (Dev Grown)

**Goal:** (1) `terraform apply` seeds Contabo `apps/data/dev/*`. (2) Deploy and verify **dev apps** + **agent apps** on Contabo Kind via Contabo Argo **gitops**, same shape as **prod fleet** ApplicationSets. Prove CSI + Google login. **Hard stop** — do not open Phase 3.

**Prereq:** [phase-1.md](phase-1.md) Grown. Contabo JWT `auth/jwt-nonprod` / `am-backend-role-dev`. Overlay: am-gitops `overlays/dev/vault-https-contabo.yaml`. Contabo Argo `https://argocd.asrax.in`. Operator kubeconfig: `~/.asrax/kubeconfig.dev`.

**Gitops model (prod-one pattern):** Mirror Contabo prod fleet sets — not laptop `am deploy`, not dig-local Argo.

| Prod (reference) | Contabo **dev** (this phase) |
|------------------|------------------------------|
| [apps-prod-fleet.yaml](../../../../am-gitops/application-sets/apps-prod-fleet.yaml) | [apps-dev-fleet.yaml](../../../../am-gitops/application-sets/apps-dev-fleet.yaml) → `am-apps-dev` |
| [agents-prod-fleet.yaml](../../../../am-gitops/application-sets/agents-prod-fleet.yaml) | [agents-dev-fleet.yaml](../../../../am-gitops/application-sets/agents-dev-fleet.yaml) → `am-agents-dev` |
| Contabo Approve / `am gitops` | Contabo Approve rolls helm image tag (no pin commit) |
| CSI `apps/data/prod` | CSI `apps/data/dev` + JWT (`vault-https-contabo`) |

Pilot remains: [gateways-nonprod-pilot.yaml](../../../../am-gitops/application-sets/gateways-nonprod-pilot.yaml) (`am-api-gateway-dev`, `am-ai-gateway-dev`). Full fleets exclude those two to avoid duplicate Apps.

## Implement

### 2a — Vault seed (Terraform) — DONE 2026-09-27

- [x] TF root [`terraform/kind-fleet/dev/vault-apps-contabo`](../../../../am-infra-automation/terraform/kind-fleet/dev/vault-apps-contabo)
- [x] Preprod Google/OIDC via `~/.asrax/vault-apps-contabo-dev.tfvars` (not in Git)
- [x] `terraform plan` — only `apps` / `dev/…` (48 add)
- [x] `terraform apply` — **36** services + infra on Contabo `apps/data/dev`

### 2b — Dev apps via Contabo Argo

- [x] Authored `application-sets/apps-dev-fleet.yaml` (prod-fleet shape; Contabo Vault overlay; ignore helm.parameters)
- [ ] **Push to am-gitops main** so Contabo Argo enrolls the AppSet
- [x] Pilot `am-api-gateway-dev` Synced/Healthy; CSI → Contabo Vault
- [ ] Full dig apps fleet Synced/Healthy after enroll

### 2c — Dev agents via Contabo Argo

- [x] Authored `application-sets/agents-dev-fleet.yaml` → `am-agents-dev` (no n8n; excludes pilot ai-gateway)
- [ ] **Push to am-gitops main** for Contabo Argo enroll
- [x] Pilot `am-ai-gateway-dev` Synced/Healthy
- [ ] Full dig agents Ready in `am-agents-dev`

### 2d — End-user prove + Dev Grown

- [ ] Google login on Contabo **dev** UI (needs identity enrolled + Ready)
- [x] Spot-check api-gateway + ai-gateway Healthy on Contabo Argo
- [ ] Mark **Dev Grown** in [README.md](README.md)

## Test

Use [tests/phase-2.md](tests/phase-2.md).

- [x] Plan showed no `prod/` Vault paths
- [x] Contabo dig secrets present (36 services); Google keys on `am-identity`
- [x] Pilot dig gateways Synced/Healthy
- [ ] Full fleets enrolled
- [ ] Google login
- [x] Preprod Kind / vault-preprod unchanged

## Grown

- [x] Contabo `apps/data/dev` seeded by TF
- [ ] Dev apps + agents fleets enrolled and verified
- [ ] Google login green
- [ ] **Dev Grown** in README → then STOP (no Phase 3 yet)

## Stop if fail

Wrong env writes, Contabo Vault down, CSI fail → fix TF; do not start preprod phases; no surgery scripts.

## Refuse

- Surgery `vault kv put` as SoT
- Laptop `am deploy` / dig-local Argo as Contabo dig SoT
- kubectl sync Applications
- n8n / platform on dig NS
- Preprod mutate / `apps/data/prod` writes
- Pointing dig CSI at `vault-preprod.asrax.in`

## Next operator step

1. Commit + push `am-gitops` AppSets (`apps-dev-fleet.yaml`, `agents-dev-fleet.yaml`).
2. Confirm Contabo Argo creates `*-dev` Applications; sync/healthy.
3. Scale/Ready identity + Google login prove → mark Dev Grown.
