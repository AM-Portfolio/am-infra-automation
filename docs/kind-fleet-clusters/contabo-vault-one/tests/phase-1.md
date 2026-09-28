# Phase 1 tests — Remap + TF outline

**Phase:** [../phase-1.md](../phase-1.md)

## Test cases

| ID | Case | Pass criteria |
|----|------|---------------|
| T1.1 | PATH_REMAP matrix | Every in-scope **dev** leaf has action: copy / skip / empty / remap |
| T1.2 | Google preference | identity / keycloak / gateway Google fields marked **preprod prefer** |
| T1.3 | Host remap | Contabo nonprod / `am_*_dev` / **dev** realm documented |
| T1.4 | Prod refuse | Explicit skip for `apps/data/prod` |
| T1.5 | TF-OUTLINE | Contabo address, state path, apply order, module `apps-vault-seed` named |
| T1.6 | No apply | No terraform state change for Contabo vault-apps in this phase |
| T1.7 | Preprod lean stub | kafka/n8n/platform SKIP listed but not executed |

## Grown

- [ ] All T1.* pass
- [ ] Ready for Phase 2 plan/apply

## Evidence

Filled PATH_REMAP + TF-OUTLINE (no secrets in Git).
