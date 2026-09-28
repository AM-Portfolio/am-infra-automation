# Phase 0 — Backups + inventory

**Goal:** Recent prod + preprod Vault backups on disk; path/key inventory filled. **No** Contabo writes. **No** preprod mutate/delete.

**Prereq:** Read [README.md](README.md) locked decisions.

## Implement

- [x] Dump Contabo **prod** Vault `https://vault.asrax.in` → `VPS/vault/backups/vault_prod_full_backup_20260927_211732.json` (53 paths; 47 prod)
- [x] Dump **preprod** Vault `https://vault-preprod.asrax.in` → `VPS/vault/backups/vault_preprod_full_backup_20260927_211238.json` (86 paths)
- [x] Catalog files in [INVENTORY.md](INVENTORY.md) (dates, path counts — **key names only**)
- [x] Diff recent trees (INVENTORY)
- [x] Note Contabo `apps/data/dev` dig pilot
- [x] List preprod remove-candidates — **document only**
- [x] July pack kept as historical fallback

## Test

Use [tests/phase-0.md](tests/phase-0.md).

- [x] Recent **preprod** backup under `VPS/vault/backups/`
- [x] Recent **Contabo prod** backup under `VPS/vault/backups/`
- [x] INVENTORY tables filled without secret values
- [x] No Contabo `apps/data/prod` or preprod Kind mutations during this phase

## Grown

- [x] Phase 0 complete; ready for Phase 1 remap / Phase 2 apply
- [x] Operator can refuse Phase 2 if dumps missing (dumps present)

## Stop if fail

Backups missing or incomplete → **do not** start TF seed (Phase 2).
## Refuse

- No `terraform apply`
- No preprod pod deletes
- No surgery seed scripts
- No committing backup JSON with secret values into Git (keep local / gitignored)
