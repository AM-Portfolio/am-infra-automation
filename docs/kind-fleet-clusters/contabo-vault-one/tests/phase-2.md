# Phase 2 tests — Vault seed + Contabo Argo apps/agents

**Phase:** [../phase-2.md](../phase-2.md)

## Test cases

### Vault (TF)

| ID | Case | Pass criteria |
|----|------|---------------|
| T2.1 | Terraform plan scope | Plan only creates/updates mount `apps` paths under `dev/…` (CSI `apps/data/dev/…`); **zero** `prod/` or `preprod/` writes |
| T2.2 | Terraform apply | Apply succeeds; state stored under Contabo vault-apps state path |
| T2.3 | Infra paths | `apps/data/dev/infra/{postgres,mongodb,redis,…}` readable (key names); hosts are Contabo **dev**/nonprod |
| T2.4 | Service catalog | Catalog services from `apps-vault-seed` present under `apps/data/dev/services/*` (covers apps **and** agents needs) |

### Dev apps (Contabo Argo — prod-fleet shape)

| ID | Case | Pass criteria |
|----|------|---------------|
| T2.5 | Apps AppSet enrolled | Contabo Argo has ApplicationSet for **dev apps** mirroring `apps-prod-fleet` → `am-vps-nonprod` / `am-apps-dev` |
| T2.6 | Apps Synced/Healthy | Enrolled `*-dev` app Applications Synced + Healthy on Contabo Argo |
| T2.7 | Apps pods Ready | `kubectl --kubeconfig ~/.asrax/kubeconfig.dev -n am-apps-dev get deploy,po` — desired deploys Available/Ready |
| T2.8 | Apps CSI | SPC mounts OK; JWT `auth/jwt-nonprod` / `am-backend-role-dev`; no TokenReview to Kind `:6443` |

### Dev agents (Contabo Argo — prod-fleet shape)

| ID | Case | Pass criteria |
|----|------|---------------|
| T2.9 | Agents AppSet enrolled | Contabo Argo has ApplicationSet for **dev agents** mirroring `agents-prod-fleet` → `am-agents-dev` |
| T2.10 | Agents Synced/Healthy | Enrolled agent Applications Synced + Healthy (excl. n8n/platform not on dig) |
| T2.11 | Agents pods Ready | `kubectl --kubeconfig ~/.asrax/kubeconfig.dev -n am-agents-dev get deploy,po` — Ready |
| T2.12 | Agents CSI | Agent pods that need Vault mount CSI successfully from `apps/data/dev/…` |

### End-user + gate

| ID | Case | Pass criteria |
|----|------|---------------|
| T2.13 | Google login | Interactive login on Contabo **dev** UI succeeds (preprod Google/OIDC values) |
| T2.14 | Agent smoke | At least one agent path (e.g. ai-gateway / mcp) responds healthy via Contabo edge |
| T2.15 | Preprod untouched | vault-preprod still serving preprod; no lean deletes |
| T2.16 | No surgery / local Argo | Deploy path was Contabo Argo / `am gitops` only — not dig-local Argo, not kubectl sync, not seed scripts |
| T2.17 | Dev Grown README | All Dev Grown checkboxes in [README.md](../README.md) checked |

## Grown

- [ ] All T2.* pass
- [ ] **Hard stop** — Phases 3–5 remain blocked until later Execute

## Evidence

`terraform plan`/`apply` summary (no tokens); Contabo Argo app/agent Health list; `kubectl` Ready counts for `am-apps-dev` + `am-agents-dev`; Google login note (pass/fail + time).
