# Phase 4 — Nonprod 1 Kind + preprod handoff

**Goal:** One Kind on other VPS (lean). **Backup preprod → sync nonprod DBs before any delete.**

**Prereq:** [phase-3.md](phase-3.md) Contabo green. Phase 0 preprod location known.

**2026-09-26 note (Contabo-only path):** Legacy `am-preprod` was already deleted (fleet TODO Phase C). There is **no** live preprod PVC/DB to dump. Phase 4 becomes: stand up **new lean nonprod/dev Kind** (Vault `apps/data/dev/`, not Contabo stores). VPS2 today is **Compose obs only (~8 GB)** — do not colocate Kind stores on that box until ≥16 GB ([VPS2_DEV_PLATFORM.md](../VPS2_DEV_PLATFORM.md)). Contabo Phases 5+ may proceed with this Contabo-only note.

## Implement

- [x] **Backup preprod** — N/A: no live preprod cluster (evidence: TODO Phase C `kind delete am-preprod`; VPS1/2 have no `am-preprod`)
- [ ] Restore/sync backup into **nonprod** DB set — N/A for PVC restore; seed nonprod from compact/`dev` sizing instead
- [ ] Stand up **one** Kind on other VPS: NS for stores + Keycloak + apps *(blocked: VPS2 undersized for stores; need host/RAM decision)*
- [ ] Compact sizing ([SIZING.md](SIZING.md)); Keycloak → **local** PG
- [ ] Vault paths `preprod/*` / `dev/*` → Contabo Vault (path ACL)
- [x] **No** full Temporal / Lago / n8n stack *(design locked)*
- [ ] Optional thin Argo only
- [ ] Ensure no Contabo `postgres.asrax.in` / hostAliases from nonprod pods
- [x] Preprod retire already done historically — do not recreate `am-preprod`

## Test

Use [tests/phase-4.md](tests/phase-4.md).

- [ ] Backup evidence recorded **before** delete
- [ ] Nonprod apps use **local** infra
- [ ] Isolation: no Contabo store FQDNs from nonprod pods
- [ ] Single Kind only on nonprod host

## Grown

- [ ] Contabo still 2 Kind + 1 DB; nonprod lean 1 Kind
- [ ] Preprod retired only after sync green

## Stop if fail

Backup incomplete → **do not delete** preprod.

## Refuse

- Delete preprod without backup evidence
- hostAliases to Contabo TCP
- Second Vault; full Lago/Temporal/n8n on nonprod
