# Prod — Phase 1 (Terraform Kind module validate)

Skill: `phase-1-tf.md` · tests `tests/phase-1.md` · Host/Kind: [SIZING.md](SIZING.md).

## Prereq

Phase 5.1 green. `am-infra-automation` checkout on operator path; apply later **from VPS1**.

## Implement

- [x] Confirm stacks only under `terraform/kind-fleet/{dev,prod,dr,obs}/` — will **not** apply `terraform/**/{local,preprod}`.
- [x] Confirm backend for prod: `/data/am-state/terraform/prod/` on VPS1 (not laptop) — `backend.hcl` paths set; dir empty (no tfstate yet).
- [x] Confirm naming: `am-prod-infra` / `am-prod-apps` / `am-prod-platform` · ports 6443/6444/6445.
- [x] **Current (64 GB):** infra **`node_shape=two`**; apps/platform **`one`** (TF stacks pass explicitly).
- [x] **Target (36 GB) known:** later unlock prod infra **`one`** — do **not** shrink mid Phase 1; see [SIZING.md](SIZING.md).
- [x] Hard-fail understood for `local` / `preprod` / `hostbet-vps` (`variables.tf` validation).

## Test

- [x] On checkout: `terraform init -backend=false` + `validate` for `kind-fleet/prod` stacks (infra/apps/platform/edge/stores/exposer) — **no apply**. All Success.
- [x] Plan/name check (throwaway `.terraform/phase1-dry.tfstate` only): `am-prod-infra` 6443/`two` · `am-prod-apps` 6444/`one` · `am-prod-platform` 6445/`one` — never `am-preprod` / `am-local`.
- [x] Output `node_shape` for infra = `two` on current hardware class.
- [x] Confirm will **not** apply prod state from laptop (SoT remains `/data/am-state/terraform/prod/` on VPS1).

## Grown

- [x] Validate still passes; no Kind clusters created by Phase 1 (VPS1: `No kind clusters found`).
- [x] Phase 5.1 still green; R2 seed objects untouched.

## Notes (session)

- Plan needs `terraform init -backend-config=path=...` (empty `backend "local" {}`); Phase 1 used throwaway dry path under `.terraform/` — never VPS path from laptop.
- `am-ops` not in `docker` group yet — Phase 2 must grant docker or use G1 carefully.
- Next: **Phase 2** ([phase-2.md](phase-2.md)) Kind + edge + stores on VPS1.

## Stop if fail / Refuse

Stay on Phase 1. No `terraform apply` / `kind create` here.
