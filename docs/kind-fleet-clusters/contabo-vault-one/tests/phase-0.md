# Phase 0 tests — Backups + inventory

**Phase:** [../phase-0.md](../phase-0.md)

## Test cases

| ID | Case | Pass criteria |
|----|------|---------------|
| T0.1 | Prod backup file | `VPS/vault/backups/vault_prod_full_backup_*.json` exists; size > 0 |
| T0.2 | Preprod backup file | `VPS/vault/backups/vault_preprod_full_backup_*.json` exists; size > 0 |
| T0.3 | Inventory docs | [INVENTORY.md](../INVENTORY.md) has dates + path counts; **no** secret values |
| T0.4 | Path/key diff | Prod vs preprod leaf table started from **recent** dumps |
| T0.5 | Read-only Contabo | No new writes under Contabo `apps/data/prod` or `apps/data/preprod` during Phase 0 |
| T0.6 | Preprod Kind untouched | No Kafka/n8n/Vault deletes; remove-candidates documented only |
| T0.7 | Fallback noted | July pack listed as historical only once recent dumps exist |

## Grown

- [ ] All T0.* pass
- [ ] No TF apply / Kind delete during Phase 0

## Evidence

Backup filenames + INVENTORY tables (path/key names only).
