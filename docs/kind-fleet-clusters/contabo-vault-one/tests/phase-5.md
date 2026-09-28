# Phase 5 tests — Retire nonprod platform stacks (one Kind keepers only)

**Phase:** [../phase-5.md](../phase-5.md)  
**Blocked until Phase 4 Grown.**

## Test cases (when unblocked)

| ID | Case | Pass criteria |
|----|------|---------------|
| T5.1 | Backup evidence | Recent preprod (+ Contabo) backup still on disk before delete |
| T5.2 | No vault-preprod dependents | No Application/CSI address `vault-preprod.asrax.in` |
| T5.3 | Vault-preprod removed | vault-preprod STS/Helm gone on **nonprod** (or scaled 0 permanently) |
| T5.4 | Kafka/n8n/platform gone | Nonprod Kind has no Running Kafka/n8n/platform stacks |
| T5.5 | Lean apps still up | `am-apps-preprod` CSI via Contabo Vault still Ready; Contabo Argo Healthy |
| T5.6 | Lean agents still up | `am-agents-preprod` CSI via Contabo Vault still Ready; Contabo Argo Healthy |
| T5.7 | Three NS only | Keepers remain: `am-apps-preprod`, `am-agents-preprod`, edge; Contabo dig NS gone |
| T5.8 | Laptop dig still up | Laptop `am-dev-apps` unchanged and healthy |
| T5.9 | Prod Kind untouched | Contabo prod Kind / prod AppSets / `apps/data/prod` unchanged |
| T5.10 | TF/gitops SoT | Retire via TF/gitops — no surgery script as SoT; deletes after user confirm |

## Grown

- [ ] T5.* pass when executed
- [ ] One Contabo Vault serves prod + lean preprod + dig paths; one nonprod Kind with three NS

## Evidence

Before/after workload + NS list; DNS note for vault-preprod; user confirm log for deletes.
