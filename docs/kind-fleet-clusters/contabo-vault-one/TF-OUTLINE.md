# TF outline — Contabo Vault Dev seed (no surgery)

Design notes for Execute. **Do not** `terraform apply` from checkboxes alone until Phase 0–1 Grown and operator starts Phase 2.

**SoT:** `terraform apply` on a Contabo-targeted vault-apps root that calls [`modules/core/apps-vault-seed`](../../../terraform/modules/core/apps-vault-seed) (`vault_kv_secret_v2` → mount `apps`, name `dev/…` → CSI path `apps/data/dev/…`).

**Refuse:** ad-hoc `seed-vault-*.ps1` / `*.sh` loops, embedded PowerShell/`null_resource` surgery as primary seed path, one-off `vault kv put`, manual Vault UI as documented operator path.

## Roots

| Root | Role |
|------|------|
| [kind-fleet/dev/vault-apps](../../../terraform/kind-fleet/dev/vault-apps) | Existing laptop/Kind **vault-dev** seed (`https://vault-dev.asrax.in`) — **not** Contabo SoT for this track |
| [kind-fleet/dev/vault-apps-contabo](../../../terraform/kind-fleet/dev/vault-apps-contabo) | **Contabo SoT** — `env=dev`, provider `https://vault.asrax.in`, separate state `~/.asrax/tfstate/dev/vault-apps-contabo/` |

## Contabo provider + inputs (locked intent)

| Input | Source |
|-------|--------|
| Vault address | `https://vault.asrax.in` |
| Vault token | Operator local only — e.g. `~/.asrax/vault-contabo-infra.json` `root_token` (never commit) |
| `env` | `dev` only (folder guard) |
| Store creds | Contabo **prod** store cluster admin from `apps/data/prod/infra/{postgres,mongodb,redis}` + dig per-DB users (`store_hosts=contabo_prod`) |
| Keycloak admin | Nonprod/dev realm admin env — prefer values consistent with working preprod Google login |
| Google / OIDC overlays | Prefer **preprod** backup values via `extra_service_data` (or equivalent) — not invent from prod |
| Realm | `am-dev-realm` (or Contabo nonprod realm in use); remap OIDC URLs to Contabo **dev** hosts |
| UI base | `https://am-dev.asrax.in` (or live Contabo **dev** UI host) |
| Dig networking | **No** hostAliases; Contabo DNS to prod store FQDNs; Vault/Argo/auth/UI over **HTTPS** |

## Apply order (Dev track only)

```text
Phase 0 backups (Vault CLI/API evidence → VPS/vault/backups/) 
  → Phase 1 PATH_REMAP + this outline locked
  → terraform -chdir=…/vault-apps-contabo init -backend-config=backend.hcl
  → terraform plan   # must show only apps/data/dev paths (mount apps, name dev/…)
  → terraform apply
  → Prove CSI + Google login → Dev Grown → STOP
```

## State

| Env | Suggested state path |
|-----|----------------------|
| Contabo Dev vault-apps | `~/.asrax/tfstate/dev/vault-apps-contabo/terraform.tfstate` (laptop) or `/data/am-state/terraform/dev/vault-apps-contabo/` (VPS) |

Separate from `~/.asrax/tfstate/dev/vault-apps/` (vault-dev).

## Prereq already live on Contabo (document; do not re-surgery)

| Item | Notes |
|------|--------|
| JWT auth | `auth/jwt-nonprod` + role `am-backend-role-dev` + policy read `apps/data/dev/*` |
| CSI overlay | am-gitops `overlays/dev/vault-https-contabo.yaml` |
| Pilot seeds | e.g. `apps/data/dev/services/am-ai-gateway` may already exist — TF owns full catalog after apply |

If JWT missing, add via **TF Vault auth resources** (preferred) or operator once — not a seed surgery script.

## Preprod track (blocked until Dev Grown)

Same prod-one Contabo Argo pattern as Phase 2, for lean preprod:

| Item | Value |
|------|--------|
| TF seed | Contabo `apps/data/preprod` lean (skip kafka/n8n/platform) — separate state |
| CSI | Overlay → `vault.asrax.in` + JWT (`am-backend-role-preprod`) — mirror dig Contabo overlay |
| Apps AppSet | Shape of `apps-prod-fleet` → `am-apps-preprod` |
| Agents AppSet | Shape of `agents-prod-fleet` → `am-agents-preprod` (excl. n8n/platform) |
| Sync | Contabo Argo / `am gitops` only |

See [phase-3.md](phase-3.md)–[phase-5.md](phase-5.md).
