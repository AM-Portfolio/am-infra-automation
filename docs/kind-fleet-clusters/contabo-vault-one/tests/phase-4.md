# Phase 4 tests — Lean preprod prove (apps + agents)

**Phase:** [../phase-4.md](../phase-4.md)  
**Blocked until Phase 3 Grown.**

## Test cases (when unblocked)

| ID | Case | Pass criteria |
|----|------|---------------|
| T4.1 | Apps healthy | Required `am-apps-preprod` pods Running; Contabo Argo Synced/Healthy |
| T4.2 | Agents healthy | Required `am-agents-preprod` pods Running; Contabo Argo Synced/Healthy |
| T4.3 | No kafka/n8n wait | No CrashLoop waiting on kafka/n8n/platform |
| T4.4 | Gap fill TF-only | Missing secrets added via TF; no surgery scripts |
| T4.5 | Google login | Contabo preprod Google login still green |
| T4.6 | Agent smoke | Agent path (ai-gateway / mcp) still healthy |
| T4.7 | Laptop dig unchanged | Laptop `am-dev-apps` CSI + apps still green (not Contabo dig) |
| T4.8 | Prod untouched | Contabo prod Kind / AppSets / `apps/data/prod` unchanged |
| T4.9 | NS keepers only | Nonprod user workloads only in `am-apps-preprod`, `am-agents-preprod`, edge |
| T4.10 | Parity note | App/agent path gaps vs prod documented; kafka/n8n gaps intentional |

## Grown

- [ ] T4.* pass when executed

## Evidence

Pod status for both NS; Argo Health list; gap-fill plan excerpt; prod/laptop spot-check notes.
