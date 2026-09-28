# DR — Phase 1 (Terraform Kind module validate)

Skill: `phase-1-tf.md` · tests `tests/phase-1.md` · Host/Kind: [SIZING.md](SIZING.md).

## Prereq

Phase 5.1 green. `am-infra-automation` checkout on operator path; apply later **from VPS3**.

## Implement

- [ ] Confirm stacks only under `terraform/kind-fleet/{dev,prod,dr,obs}/` — will **not** apply `terraform/**/{local,preprod}`.
- [ ] Confirm backend for DR: `/data/am-state/terraform/dr/` on VPS3 (not laptop).
- [ ] Confirm naming: `am-dr-infra` / `am-dr-apps` / `am-dr-platform` · ports 6443/6444/6445.
- [ ] **All `node_shape=one`** (DR never uses two-node infra).
- [ ] Hard-fail understood for `local` / `preprod` / `hostbet-vps`.
- [ ] If Kind already exists (prior G1): inventory only — **do not recreate** unless user confirms clean.
- [ ] Later phases: **adopt** (`scripts/kind-fleet/adopt-kind-cluster.sh` / `terraform import`) — refuse `kind delete` for TF ownership.

## Test

- [ ] `terraform init -backend=false` + `validate` for `kind-fleet/dr` stacks (infra/apps/platform/edge/stores/exposer) — **no apply**.
- [ ] Name check: `am-dr-*` — never `am-preprod` / `am-local` / `am-prod-*` on this host.
- [ ] Output `node_shape` = `one` for all three.
- [ ] Confirm will **not** apply DR state from laptop.

## Grown

- [ ] Validate still passes.
- [ ] Phase 5.1 still green; R2 seed objects untouched.

## Stop if fail / Refuse

Stay on Phase 1. No `terraform apply` / `kind create` here (unless Execute + G1 for missing clusters).
