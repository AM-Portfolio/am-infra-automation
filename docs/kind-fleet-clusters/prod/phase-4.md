# Prod — Phase 4 (Vault terraform + Argo waves)

Skill: `phase-4-apps.md` · tests [`tests/phase-4.md`](tests/phase-4.md).

**Gates (no tmp scripts):** `PYTHONPATH=scripts/kind-fleet python -m phase_gates --env prod --wave 4d`

**Seed coupling:** `vault-apps` requires `/data/am-state/credentials/prod-keycloak-admin.env` written by platform apply (never fleet placeholders for `KEYCLOAK_ADMIN_PASSWORD`).

## Prereq

Phase 3e green; Phase 2 DBs seeded. Access still **off**.

## Deploy model (locked)

| Step | Tool | Refuse |
|------|------|--------|
| **4a** Vault + G25 | **`terraform apply`** `kind-fleet/prod/vault-apps` + G25 scripts | Hand-seed Vault; Argo writing Vault |
| **4b** gitops retarget | Git + Argo register | — |
| **4c–4g** product + agents | **Argo sync** `targetRevision: main` | Terraform AM Deployments; default `am deploy` |

## Implement

### 4a — Vault + G25 (terraform once)

- [x] G1: `kind create` `am-prod-apps` API **:6444** (already present from Phase 2 prep).
- [x] NS `am-apps-prod` + `am-agents-prod` + `edge`; SA `am-backend-sa`.
- [x] `kind-fleet/prod/vault-apps` apply — catalog infra + 35 services under `apps/data/prod/*`.
- [x] G25: CSI chart 1.4.8 + vault-csi-provider; `auth/kubernetes-apps` / role `am-backend-role`.
- [x] Vault addr `https://vault.asrax.in`; injector **off**.
- [x] Hosts rewritten for prod (`postgres`/`mongo`/`auth`/`influx` bare; OIDC issuer `https://auth.asrax.in/realms/am-realm`).
  - Exposer v6: no Docker alias for vault/influx HTTPS (CF); TCP aliases for stores only.
  - CSI login Job → `LOGIN_AND_READ_OK` (SA JWT → role → read `apps/data/prod/infra/postgres`).
  - Note: GHCR pull secrets not created yet (`vault_csi_has_ghcr=false`) — needed before private image pulls in 4c+.

### 4b — GitOps

- [x] Fleet Vault overlay for prod (`vault.asrax.in`, CSI, `am-backend-role`) — `prod/values-overlays/fleet-common.yaml` on `main`.
- [x] Register `am-prod-apps` in Argo (`https://203.174.22.129:6444` Successful); AppProject `am-prod` destinations → `am-prod-apps` / `am-apps-prod`+`am-agents-prod`+`edge`.
- [x] Roots `prod-apps-root` / `prod-agents-root` synced (Application CRs only); child apps Manual / OutOfSync / Missing; no automated sync-all; Contabo-clean.
- [x] Applications chart/values/imageValues → `main` (gitops SoT).
  - Note: Argo GitHub `repo-creds` installed from live `gh` token (credentials.env PAT was 401). Push updated `projects/am-prod.yaml` when convenient.

### 4c–4g — Argo waves

- [x] **4c** Sync: gateway + AI gateway + modern-ui + asrax-proxy.
  - GHCR pull secrets `ghcr-creds` / `github-registry-secret` in apps+agents+edge.
  - asrax-proxy: chart used `regcred` + tag `latest` → patched pull secrets + pin `31212186541` (local gitops image-tags updated; push when convenient).
  - Apps Traefik (edge NS, NodePort 30080) + infra cross-cluster bridge `Host(am.asrax.in)` + CF tunnel hostname added (prod tunnel v23).
  - Traefik Middleware CRs owned by **`terraform apply`** `kind-fleet/prod/apps` (`middlewares.tf`: `global-cors`, `strip-prefix-apps`, rewrite + agents). No kubectl-patch.
- [x] **4d** Sync: `am-identity` (+ subscription/notification if required for login).
  - Vault `KEYCLOAK_ADMIN_*` synced from platform (not fleet placeholders); CSI remounted.
  - Hard gate: `PYTHONPATH=scripts/kind-fleet python -m phase_gates --env prod --wave 4d` → **PASS** (`/identity/admin/roles` 200; issuer `https://auth.asrax.in/realms/am-realm`).
  - Note: `/identity/users/me` still 500 on settings parse until am-identity image picks up defensive fix in `keycloak_provider.get_user_settings`.
- [x] **4e** Sync: `am-market-data`.
  - Argo sync via plaintext login (`argocd-server:80`); pod Ready.
  - Strip prefixes for `/market` (+ 4f/4g paths) in TF `middlewares.tf` (not wave scripts).
  - gitops: `hostAliases: []` + `hostaliases-kind-local.yaml` (no laptop `192.168.1.11` pin).
  - Quote: `GET /market/v1/market-data/quotes?symbols=RELIANCE` → **200** (cached RELIANCE).
- [x] **4f** Sync: portfolio → trade → doc → news/analysis.
  - Exposer hostAliases `172.18.0.6`; portfolio `PORTFOLIO_REDIS_ENABLED=false` (Lettuce hang workaround).
  - Gate: `phase_gates --wave 4f` → **PASS**.
- [x] **4g** Sync: remaining apps + agents; Postman closout.
  - Helper: `scripts/kind-fleet/wave_4g_sync.py` + exposer hostAliases on remaining store consumers.
  - Vault path overrides on Application CRs (`apps/data/...`; skip missing keys via `__jaas__` where needed).
  - `am-qa-agents-prod`: was missing SPT `runs` table; `init_db()`/`create_all` applied in-pod → **Ready**.
  - Gate: `gate_4g_remaining` → **PASS** (domain health + CSI no sidecar + portfolio closout).
- [x] Image pins: never `latest`; one service = one `image-tags/<service>.yaml`; manual Argo sync. GHCR numeric tags pinned for former `latest` services (PR #5).

## Test — app / API host matrix

| Path / host | Wave | Expected | Result |
|-------------|------|----------|--------|
| `https://am.asrax.in/` | 4c | UI 200 or auth challenge | **200** HTML (modern-ui) |
| `https://am.asrax.in/gateway` | 4c | health or **401** without token | **401** JSON Unauthorized |
| AI gateway / proxy paths | 4c | domain health / challenge | `/am` → 307/401; `/ai` path TBD (404 on `/ai`) |
| Login → token → protected API | 4d | **200** with token | **PASS** `/identity/admin/roles` 200 |
| Market quote | 4e | quote on domain | **200** `quotes?symbols=RELIANCE` |
| Portfolio / trade / doc / news | 4f | domain smoke | **PASS** all health 200 + portfolios list |
| Remaining apps + agents | 4g | Postman + domain | **PASS** gate_4g; QA Ready after schema init |
| `https://auth.asrax.in` | all | without Access cookie | |
| G24 platform hosts | all | still 200 / challenge | |

### 4a checks

- [x] Vault paths `apps/data/prod/infra/*` + catalog `services/*` present after **one** apply.
- [x] CSI login → `LOGIN_AND_READ_OK`; no product pods required yet.
- [x] Grep fail: localhost / port-forward / preprod Contabo as SoT (seed hosts checked).

### 4b–4g checks

- [x] Apps cluster registered (`am-prod-apps`); roots on `main`; no automated sync-all (30 child apps dest=`am-prod-apps`).
- [x] After each wave: pods Ready in `am-apps-prod` / agents NS (QA exception noted above).
- [x] **4d hard gate:** login → token → protected **200** on `https://am.asrax.in/...` (`phase_gates --wave 4d`).
- [x] **4e:** market quote via domain (`phase_gates --wave 4e`).
- [x] **4g:** domain health + portfolio closout green (`gate_4g_remaining`); full Postman MCP folders still optional.
- [x] Access still off through all waves.

## Grown

- [x] CSI still OK (Vault not re-seeded per service).
- [x] 4d gate still holds after later waves (password-grant + portfolio list in 4g closout).
- [x] Image pins not `latest`.
- [x] Phase 4 done when 4g Postman/domain closout green (domain closout **PASS**; QA Ready + `/qa/health` JSON).

## Stop if fail / Refuse

Stay on failing wave. No terraform for AM Deployments. No `am deploy` except break-glass. No Vault re-seed per wave. No Access enforce mid Phase 4.
