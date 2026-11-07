# IAM-2 tests — every dig service user

Inventory count must match catalog. Fill pass/fail as you go.

## Counts

| Engine | Catalog | Live inventory | Match |
|--------|---------|----------------|-------|
| mongodb | | | [ ] |
| postgresql | | | [ ] |
| redis | | | [ ] |
| kafka | | | [ ] |
| minio | | | [ ] |

## Per-user checks

| User | Engine | Own access | Deny other | Pass |
|------|--------|------------|------------|------|
| (fill from inventory) | | [ ] | [ ] | [ ] |

## Fleet

- [ ] Dig app pods still Ready (shared Vault until IAM-V)
- [ ] Vault has **no** new `infra/db-users/*` paths from this phase
