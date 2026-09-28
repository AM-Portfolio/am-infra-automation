# PATH_REMAP — Contabo `apps/data/dev` (Dev track)

**Scope now:** Dev only. Preprod lean remaps stubbed at the bottom — **blocked until Dev Grown**.

Schema SoT: [VPS/vault/VAULT_SCHEMA.md](../../../../VPS/vault/VAULT_SCHEMA.md).  
Value SoT (2026-09-27): [vault_preprod_full_backup_20260927_211238.json](../../../../VPS/vault/backups/vault_preprod_full_backup_20260927_211238.json) — prefer `apps/data/preprod/…` (Google login known-good). Contabo prod live dump **blocked** (530); July pack for extra prod key shape if needed.

## Path map

| Backup / legacy key | Contabo CSI / TF write |
|---------------------|------------------------|
| `apps/data/{env}/infra/…` | mount `apps`, name `{env}/infra/…` → CSI `apps/data/{env}/infra/…` |
| `apps/data/{env}/services/…` | mount `apps`, name `{env}/services/…` → CSI `apps/data/{env}/services/…` |
| `apps/{env}/…` (July logical) | Same Contabo write as `apps/data/{env}/…` |
| `secret/{env}/…` | Remap to canonical `apps/data/{env}/…` per VAULT_SCHEMA; do not seed legacy paths |

## Value rules for **dev**

| Field class | Rule |
|-------------|------|
| Store hosts / URLs | Contabo **prod** store FQDNs (`mongo.asrax.in` / `mongodb.asrax.in`, `redis.asrax.in`, `postgres.asrax.in`) — **no** `*-dev` store plane on Contabo dig |
| Networking | **Refuse** pod `hostAliases` / Docker exposer IP pins; Contabo DNS/routing only; control plane **HTTPS** (`vault.asrax.in`, auth, Argo, UI) |
| DB users | **Different user per DB** — dig-scoped `am_*_user_dev` with unique passwords (not one shared admin for apps; not prod app users) |
| Keycloak realm / OIDC issuer | Contabo **dev** realm (`am-dev-realm` or live nonprod) |
| Google client ID/secret | Prefer **recent preprod** `apps/data/preprod/services/am-identity` (+ am-auth) |
| Google redirect URIs | Adjust to Contabo **dev** UI host (`https://am-dev.asrax.in/callback` or live) |
| Kafka | Contabo prod `kafka.asrax.in` if needed; **SKIP** for lean preprod later |
| Contabo `apps/data/prod` | **never** write |

## Action matrix (locked from 2026-09-27 preprod dump)

| Path leaf | Source values | Action → Contabo |
|-----------|---------------|------------------|
| `infra/postgres` | `apps/data/preprod/infra/postgres` | remap-value → `apps/data/dev/infra/postgres` |
| `infra/mongodb` | preprod | remap-value |
| `infra/redis` | preprod | remap-value |
| `infra/kafka` | preprod | remap-value (**dev only**) |
| `infra/influxdb` | preprod | remap-value |
| `infra/observability` | preprod | remap-value |
| `infra/shared-api` | preprod | remap-value |
| `services/am-identity` | **preprod** Google/OIDC | remap-value (keep Google secrets; realm/hosts → dig) |
| `services/am-auth` | **preprod** Google | remap-value |
| `services/am-api-gateway` | preprod (missing on dig tree today) | remap-value — **required** for dig fleet |
| `services/am-agents-mcp-gateway` | preprod | remap-value — agents fleet |
| `services/am-mcp-server` | preprod | remap-value — agents fleet |
| `services/am-mkt-agents` | preprod | remap-value — agents fleet |
| `services/am-ai-gateway` | preprod / dig pilot | remap-value (TF owns) |
| `services/am-email-extractor` | preprod | remap-value |
| `services/am-news` | preprod | remap-value |
| `services/am-oms` | preprod | remap-value |
| Other `services/*` present on dig+preprod | prefer preprod | remap-value via `apps-vault-seed` + `extra_service_data` |
| Anything under `apps/data/prod` | — | **skip / refuse** |

## Preprod lean stub (Phase 3+ — blocked)

| Path | Lean preprod |
|------|----------------|
| `infra/kafka` | **SKIP** — do not seed |
| n8n / Temporal / Lago / platform secrets | **SKIP** |
| Core stores + remaining app/agent services | Seed after Dev Grown |
| Google / OIDC | Keep preprod known-good when re-homing to Contabo Vault |
