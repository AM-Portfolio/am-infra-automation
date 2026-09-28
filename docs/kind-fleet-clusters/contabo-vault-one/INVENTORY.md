# Inventory — Contabo Vault one

**No secret values in this file.** Path/key names and file dates only.

## Backup files (`VPS/vault/backups/`)

| File | Env | Date | Path count | Notes |
|------|-----|------|------------|-------|
| `vault_preprod_full_backup_20260927_211238.json` | **preprod** (also has dig/prod/dr trees) | 2026-09-27 | **86** | Recent — `https://vault-preprod.asrax.in` |
| `inventory_path_keys_preprod_20260927_211238.json` | path/keys only | 2026-09-27 | 86 | Safe to reference in docs |
| `vault_prod_full_backup_20260927_211732.json` | Contabo **prod** (+ sparse dig/preprod) | 2026-09-27 | **53** | Recent — `https://vault.asrax.in` (47 prod / 4 dig / 2 preprod) |
| `inventory_path_keys_prod_20260927_211732.json` | path/keys only | 2026-09-27 | 53 | Contabo path/key names |
| `vault_prod_preprod_before_restore_20260928_001328.json` | prod-Vault **preprod** (pre-restore) | 2026-09-28 | **2** | Safety dump before restore (shared/cloudinary + shared/google only) |
| `preprod_restore_remap_report.json` | remap report | 2026-09-28 | 38 | Host remaps only — **no secret values** |
| `vps_vault_full_backup_20260714_214845.json` | mixed | 2026-07-14 | ~100 | Historical fallback |
| `latest.json` | mixed | 2026-07-14 | ~100 | Same as July pack |

## Preprod restore onto prod Vault (2026-09-28)

| Item | Value |
|------|--------|
| Source | `vault_preprod_full_backup_20260927_211238.json` — **only** `apps/data/preprod/*` (38 paths) |
| Target | `https://vault.asrax.in` (prod Vault cluster) |
| Script | `VPS/scripts/restore_preprod_to_prod_vault.py` |
| Host remap | `*.infra.svc.cluster.local` → `postgres\|mongo\|redis\|kafka\|influxdb.asrax.in`; `grafana.munish.org` → `grafana.asrax.in`; drop localhost from CORS |
| Not written | `apps/data/dev`, `apps/data/prod`, `apps/data/dr`, `secret/` |
| Verified | 38 leaf paths; infra hosts `*.asrax.in`; `am-identity` still has Google key names |
| CSI cutover | **Phase 3b in progress 2026-09-28** — JWT role `am-backend-role-preprod` created; overlays pushed `057acb6`; SPC sample `am-api-gateway` → `vault.asrax.in` / `jwt-nonprod` / `am-backend-role-preprod`. Contabo dig NS delete **pending user confirm**. |

## Contabo live after Phase 2 TF seed

| Path | Status |
|------|--------|
| `https://vault.asrax.in` | Healthy (seeded 2026-09-27) |
| `apps/data/dev/services/*` | **36** services via `vault-apps-contabo` TF |
| `apps/data/dev/infra/*` | postgres, mongodb, redis, kafka, influxdb, observability, shared-api |
| Google on `am-identity` | Overlaid from preprod backup via local tfvars |
| Dig AppSets | Authored locally: `application-sets/apps-dev-fleet.yaml`, `agents-dev-fleet.yaml` — **need push/enroll on Contabo Argo** |
| Dig pilot | `am-api-gateway-dev` / `am-ai-gateway-dev` Synced/Healthy on Contabo Argo |

Credentials side packs (under `VPS/vault/credentials/` — do not commit values into docs):

| File pattern | Use |
|--------------|-----|
| `ENV_DATA_PLANE_CREDENTIALS_*` | Infra host/user remaps |
| `PHASE6_VAULT_ONE_CRED_*` | One-Vault migration notes |
| `VAULT_ROLLBACK_*` | Rollback evidence only |

## Recent preprod dump (2026-09-27) — prefix counts

| Prefix | Count |
|--------|------:|
| `apps/data/preprod/…` | 38 |
| `apps/data/dev/…` | 30 |
| `apps/data/prod/…` | 2 (sparse on this Vault) |
| `apps/data/dr/…` | 2 |
| `secret/…` (legacy) | 14 |

### `apps/data/preprod/services` leaves

am-agents, am-agents-mcp-gateway, am-analysis, am-api-gateway, am-asrax-corp, am-asrax-proxy, am-auth, am-cloudinary-manager, am-doc-intelligence, am-document-processor, am-email-extractor, am-gateway, am-identity, am-lago, am-market-data, am-market-data-scheduler, am-mcp-server, am-mkt-agents, am-news, am-notification, am-novu, am-oms, am-parser, am-portfolio, am-subscription, am-trade-management, am-user-platform, logging

### `apps/data/preprod/infra` leaves

influxdb, kafka, mongodb, observability, postgres, redis, shared-api

### `apps/data/dev/services` leaves (on vault-preprod today)

am-agents, am-analysis, am-asrax-corp, am-asrax-proxy, am-auth, am-cloudinary-manager, am-doc-intelligence, am-document-processor, am-gateway, am-identity, am-lago, am-market-data, am-market-data-scheduler, am-notification, am-novu, am-parser, am-portfolio, am-subscription, am-trade-management, am-user-platform, logging

**In preprod services but missing under dig on this dump:** am-agents-mcp-gateway, am-api-gateway, am-email-extractor, am-mcp-server, am-mkt-agents, am-news, am-oms

### Google / OIDC key names (preprod `am-identity` — names only)

ALLOWED_GOOGLE_REDIRECT_URIS, AM_IDENTITY_CLIENT_ID, AM_IDENTITY_CLIENT_SECRET, AM_MCP_CLIENT_ID, AM_MCP_CLIENT_SECRET, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, KEYCLOAK_ADMIN_PASSWORD, KEYCLOAK_ADMIN_USER, KEYCLOAK_REALM, KEYCLOAK_URL, OIDC_AUDIENCE, OIDC_DISCOVERY_URL, OIDC_ISSUER, OIDC_JWKS_URL, OIDC_TOKEN_URL

## Historical July path prefix counts (fallback for Contabo prod shape)

| Prefix | Count |
|--------|------:|
| `apps/dev/…` | 26 |
| `apps/preprod/…` | 28 |
| `apps/prod/…` | 26 |
| `secret/…` | ~19 |

## Contabo live (pilot — read-only note)

| Path | Status |
|------|--------|
| `https://vault.asrax.in` | **DOWN from laptop** — CF 530 (2026-09-27) |
| Contabo MCP `user-vault` | Same 530 on `sys/mounts` |
| `apps/data/dev/services/am-ai-gateway` | Seeded in prior Contabo dig pilot (when Vault was up) |
| `apps/data/dev/…` full catalog | **Pending** Phase 2 TF apply (needs Contabo Vault healthy) |
| `apps/data/preprod/…` on Contabo | **Restored 2026-09-28** (38 paths); CSI cutover = Phase 3b |
| `apps/data/prod/…` | Alignment only — never overwrite from this track |

Auth (dig CSI): `auth/jwt-nonprod` / `am-backend-role-dev` — see am-gitops `overlays/dev/vault-https-contabo.yaml`.

## Contabo nonprod — one Kind keepers (Phases 3–5)

| Keep | Role |
|------|------|
| Kind `am-vps-nonprod` | Single Contabo nonprod Kind |
| NS `am-apps-preprod` | Lean preprod apps |
| NS `am-agents-preprod` | Lean preprod agents |
| NS edge (`traefik` + `cloudflared`) | Minimal Traefik + Cloudflare tunnel |

**Out of scope (do not delete / do not mutate):** Contabo **prod** Kind; laptop dig `am-dev-apps`.

## Contabo nonprod — remove candidates (Phase 3 inventory → Phase 5 delete)

Fill live names during Phase 3a. Delete only after Phase 4 Grown + **user confirm**.

| Category | Examples | Phase | Action now |
|----------|----------|-------|------------|
| Contabo dig NS | `am-apps-dev`, `am-agents-dev` on Contabo (not laptop) | 3f drain | Inventory + soft-delete AppSets; NS delete after confirm |
| Contabo dig AppSets | Contabo Argo Apps targeting Contabo dig NS | 3f | Disable / remove from Contabo Argo |
| Vault | vault-preprod STS/Helm / injector; DNS `vault-preprod.asrax.in` | 5 | Inventory only until Phase 5 |
| Messaging | Kafka brokers / UI on nonprod | 5 | Inventory only |
| Automation | n8n on nonprod | 5 | Inventory only |
| Platform | Temporal / Lago / full platform on nonprod if present | 5 | Inventory only |
| Extra NS | Any NS beyond the three keepers | 5 | Inventory → confirm → wipe |

### Phase 3a live fill-in (operator)

| Item | Value (fill when inventoried) |
|------|-------------------------------|
| Kind cluster name(s) on nonprod host | **`am-vps-nonprod`** (context same) — inventoried 2026-09-28 |
| Namespaces present | `am-apps-preprod`, `am-apps-dev`, `am-agents-dev`, `am-apps-prod`, `argocd`, `infra`, `vault`, `identity`, `monitoring`, `n8n`, `github-actions`, `local-path-storage`, kube-* |
| Contabo Argo Apps → Contabo dig NS | **None** — Contabo Argo `*-dev` Apps dest=`am-dev-apps` (cluster secret **missing** on Contabo; only `am-vps-nonprod` registered). Contabo dig NS pods are **orphans** leftover. |
| Contabo Argo Apps → vault-preprod | Preprod Apps still used overlay `vault-https-preprod` / fleet-common → vault-preprod until Phase 3b push |
| Kafka / n8n / platform workloads | `infra`: kafka, mongodb, postgresql, redis, traefik, cloudflared-asrax-{dev,preprod}; `vault`: vault-0 + injector; `n8n` NS empty |
| Edge NS actual name(s) | **Not separate NS** — Traefik + cloudflared live in **`infra`** today (Phase 5 shrink) |
| Keepers | `am-apps-preprod` (exists); `am-agents-preprod` (**created** Phase 3); edge keep Traefik+cloudflared-preprod in `infra` until Phase 5 |
| Operator kubeconfig | `~/.asrax/kubeconfig.preprod` (context `preprod`) — see am-gitops [KUBECONFIG.md](../../../../am-gitops/docs/KUBECONFIG.md) |
| Remove candidates | Contabo `am-apps-dev` / `am-agents-dev` (orphan pods); Contabo Argo orphan `*-dev` Apps; `am-apps-prod` on nonprod; vault-preprod STS; kafka/stores in infra (Phase 5) |

## Recent dump checklist (Phase 0)

- [ ] `vault_prod_full_backup_*.json` from Contabo `vault.asrax.in` — **BLOCKED** (530); marker file written
- [x] `vault_preprod_full_backup_20260927_211238.json` present
- [x] Path/key inventory from recent preprod dump
- [x] No secret values pasted into this repo
- [ ] Re-run Contabo prod dump when `vault.asrax.in` health returns 200

### Diff (recent vault-preprod trees)

| Leaf | In apps/data/prod (sparse) | In apps/data/preprod | Copy-to-Contabo-dev? |
|------|----------------------------|----------------------|----------------------|
| services/am-identity | yes | yes | yes (prefer preprod Google/OIDC) |
| services/am-agents | yes | yes | yes |
| services/am-api-gateway | no (on this dump) | yes | yes |
| infra/* | no | yes (incl. kafka) | yes for dig; kafka OK on dig; SKIP kafka for lean preprod later |
| agents extras (mcp, mkt, oms, news, email-extractor) | no | yes | yes for dig fleet |
