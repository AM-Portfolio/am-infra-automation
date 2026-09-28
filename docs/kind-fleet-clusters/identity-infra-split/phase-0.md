# Phase 0 — Inventory

**Goal:** Document current 3-Kind Contabo vs target 2-Kind + 1 DB stack; R2; preprod; DR/nonprod hosts. No mutations.

**Prereq:** Read [README.md](README.md) locked decisions.

## Implement

- [x] List store modules under `terraform/kind-fleet/prod/stores/` — see [INVENTORY.md](INVENTORY.md)
- [x] List platform modules — Keycloak **move**; platform Kind **retire** ([INVENTORY.md](INVENTORY.md))
- [x] Kind ports: keep infra+apps; **drop** platform :6445
- [x] Confirm **one** Contabo DB stack for platform tools + apps
- [x] Vault path map prod vs preprod/dev
- [x] Document `auth.asrax.in` bridge today (cross-cluster NodePort) → target in-cluster
- [x] R2: `asrax-disaster` failover SoT vs `asrax-db-backups` seed
- [x] Preprod data location / approximate size — **none live** (`am-preprod` already deleted; Phase 4 Contabo-only note)
- [x] Nonprod + DR host / kubeconfig / TF state paths (table in INVENTORY)
- [x] TF state dirs ↔ kubeconfig

## Test

Use [tests/phase-0.md](tests/phase-0.md).

- [ ] Inventory table filled (stores / platform / Kind ports / R2 / hosts)
- [ ] Target Kind counts stated: prod 2 / DR 1 / nonprod 1
- [ ] Auth bridge note matches live Traefik

## Grown

- [ ] Phase 0 complete; no cluster mutations
- [ ] Ready for Phase 1

## Stop if fail

Missing inventory → do not start Phase 1.

## Refuse

- No terraform apply / Kind delete
- No Keycloak restart “to check”
- No rewriting finished `prod/phase-*.md` boxes
