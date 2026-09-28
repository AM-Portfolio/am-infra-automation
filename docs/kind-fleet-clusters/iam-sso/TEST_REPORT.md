# IAM SSO — TEST REPORT

**Date:** 2026-09-26  
**Env:** prod `*.asrax.in`  
**Plan:** IAM SSO detailed testing + amctl Cursor MCP  
**Catalog:** [TESTING.md](TESTING.md) · [CONSOLE_MATRIX.md](CONSOLE_MATRIX.md)

## Executive summary

| Result | Count | Notes |
|--------|------:|-------|
| Pass | 4 | OIDC discovery; no Authentik; Grafana MCP datasources; am product UI domain |
| Partial | 8 | Domain up but SSO login / MCP realm not proven |
| Fail / gap | 11 | Many platform UIs 404; Keycloak MCP still on legacy realm until MCP restart |
| Blocked | 3 | Browser role matrix; kubectl OIDC live; Vault MCP 403 |

**Verdict:** Foundation discovery is green. Full SSO prove (login per persona) is **not** complete — Keycloak Admin MCP must be restarted against fleet `am-realm`, and several console hostnames return 404 (not wired or CF route missing).

## Step 0 — amctl / Cursor MCP

| Step | Result |
|------|--------|
| `am ai status` | ok — Cursor detected; credentials present |
| `am creds doctor` | ok — Keycloak/Argo/Grafana overlays present |
| `am ai sync` | ok |
| `am ai mcp-sync --ide cursor --host-launchers` | ok — restored keycloak, argocd, vault, grafana, … (50 servers in mcp.json) |
| Keycloak MCP smoke | **partial** — process still listed realms `am-preprod-realm` + `master` (legacy). No `am-realm` until MCP host reload |
| Credentials fix | `~/.asrax/credentials.d/infra.env`: `KEYCLOAK_URL=https://auth.asrax.in` (removed `/auth`), `KEYCLOAK_REALM=am-realm` |
| Argo MCP (prod) | `argocd_status` auth_token_set=true; `list_applications` returned HTTP 404 (API path/server mismatch) |
| Vault MCP | `list_mounts` → **403** permission denied |
| Grafana MCP | Loki + Prometheus health **OK**; Tempo unhealthy (plugin) |

**Operator:** Reload Cursor MCP (or restart IDE) so Keycloak launcher picks up new `KEYCLOAK_URL` / `KEYCLOAK_REALM`. Confirm `list_realms` includes `am-realm`.

## MCP realm snapshot (current session — legacy)

| Item | Value |
|------|-------|
| Realms seen | `am-preprod-realm`, `master` |
| Roles on preprod | `admin`, `super_admin`, `user`, `viewer`, `service` — **not** `am-*` |
| SSO max (preprod) | 36000s (10h) — not the iam-sso 24h target |
| Fleet public issuer | `https://auth-dr.asrax.in/realms/am-realm` (via `auth.asrax.in` discovery) |

## Perf summary (unauth landing)

SLO: discovery &lt; 2s · landing &lt; 5s. Times from `curl` `time_total`.

| Surface | URL | HTTP | ms | SLO |
|---------|-----|------|---:|-----|
| OIDC discovery | auth.asrax.in/…/openid-configuration | 200 | 894 | pass |
| OIDC discovery DR | auth-dr.asrax.in/… | 200 | 1007 | pass |
| Auth root | auth.asrax.in/ | 500 | 625 | fail (page) |
| Argo CD | argocd.asrax.in/ | 404 | 645 | fail |
| Vault UI | vault.asrax.in/ui/ | 200 | 1270 | pass |
| Headlamp | headlamp.asrax.in/ | 404 | 810 | fail |
| Lago | lago.asrax.in/ | 404 | 602 | fail |
| Langfuse | langfuse.asrax.in/ | 404 | 911 | fail |
| Temporal | temporal.asrax.in/ | 404 | 627 | fail |
| LiteLLM | litellm.asrax.in/ | 404 | 912 | fail |
| Grafana | grafana.asrax.in/ | 302 | 773 | pass (redirect) |
| MinIO | minio.asrax.in/ | 200 | 897 | pass |
| Kafka UI | kafka-ui.asrax.in/ | 200 | 603 | pass |
| pgAdmin | pgadmin.asrax.in/ | 302 | 924 | pass |
| Mongo Express | mongo-express.asrax.in/ | 500 | 682 | fail |
| Redis UI | redis-ui.asrax.in/ | 200 | 1083 | pass |
| Influx | influx.asrax.in/ | 200 | 627 | pass |
| n8n | n8n.asrax.in/ | 404 | 920 | fail |
| GrowthBook | growthbook.asrax.in/ | 404 | 598 | fail |
| OpenProject | openproject.asrax.in/ | 404 | 606 | fail |
| Novu | novu.asrax.in/ | 404 | 884 | fail |
| Traefik | traefik.asrax.in/dashboard/ | 200 | 587 | pass |
| modern-ui | am.asrax.in/ | 200 | 621 | pass |

Outliers: none &gt; 5s. Discovery under 2s. Auth root 500 and many 404s are availability gaps, not slow.

## Use-case results

### UC-01 Realm foundation — **partial**

- Discovery 200; issuer `auth-dr.asrax.in/realms/am-realm`; **no Authentik** — **pass**
- `am-*` roles / 24h TTL / G24 clients via Admin API — **blocked** until Keycloak MCP reloads to `am-realm`
- Admin API path: `https://auth.asrax.in/admin/serverinfo` → 401 (endpoint exists; needs fleet admin creds)

### UC-02 Persona roles — **blocked**

MCP session has no `am-ops` / `am-admin` / `am-user` on connected realm. After MCP reload + correct admin password for fleet Keycloak, assign/verify via `search_users` + realm roles.

### UC-03 Keycloak Admin — **partial**

Expect `am-admin` only. Not browser-tested. Auth console root returns 500 (routing/UI issue). Admin API present (401).

### UC-04 Argo CD — **fail (domain) / partial (MCP)**

HTTP 404 on `argocd.asrax.in`. Prod Argo MCP authenticated but `list_applications` 404. Login role matrix not run.

### UC-05 Vault UI — **partial**

`/ui/` → 200 (1270 ms). Vault MCP list mounts 403. OIDC login / role matrix not run.

### UC-06 Headlamp — **fail (domain)**

404. Fleet Headlamp module may not be applied yet.

### UC-07 kubectl OIDC — **blocked**

Not executed (needs VPS API + oidc-login + apiserver OIDC applied). Stub remains [kubeconfig.oidc.example.yaml](kubeconfig.oidc.example.yaml).

### UC-08 Lago / Langfuse / Temporal / LiteLLM — **fail (domain)**

All four hostnames 404.

### UC-09 Grafana / MinIO — **partial**

Grafana 302 (773 ms); Grafana MCP datasources healthy. MinIO 200. Login role matrix not run.

### UC-10 Store UIs — **partial**

kafka-ui / redis-ui / influx 200; pgAdmin 302; mongo-express 500. OIDC/proxy login not proven.

### UC-11 Platform UIs — **fail / partial**

n8n, growthbook, openproject, novu → 404. Traefik dashboard 200.

### UC-12 Product UI — **partial (domain pass)**

`am.asrax.in` 200. `am-user` vs ops login not browser-proven.

### UC-13 Perf summary — **pass (measured surfaces)**

All successful timings under 5s; discovery under 2s.

## 404 fix (2026-09-26 follow-up)

**Cause:** Bare platform CNAMEs pointed at **asrax-dr-tunnel**; DR Traefik has no platform IngressRoutes. Contabo already had routes/pods.

**Actions:**
1. Cloudflare DNS: retargeted `argocd`, `lago`, `langfuse`, `temporal`, `litellm`, `n8n`, `growthbook`, `openproject`, `novu`, `auth` → **asrax-prod-tunnel**
2. Added `headlamp.asrax.in` to Contabo tunnel ingress; deployed Headlamp helm + IngressRoute on `am-prod-infra`
3. Patched n8n IngressRoute → Service `n8n-main`; TF fix in `modules/apps/n8n/gateway.tf`

**Re-probe:** majors return 200/302 (auth `/` 302; discovery still 200).

1. Reload Cursor MCP after `infra.env` Keycloak URL/realm fix; verify `list_realms` → `am-realm` and `list_realm_roles` → `am-*`.
2. Apply iam-sso platform/stores wiring (Headlamp, oauth2-proxy, Argo route) so majors stop returning 404.
3. Re-run browser SSO with `am-ops` / `am-admin` / `am-user` passwords from Vault (do not commit).
4. Fix Argo MCP API base if Contabo vs Kind path drift.
5. Grant Vault MCP a read policy (not root) for health checks.

## CONSOLE_MATRIX test ticks (this run)

Only domain+discovery proven — login columns stay unchecked:

| Surface | test |
|---------|------|
| Keycloak discovery (not Admin UI) | domain OK; Admin UI not green |
| Grafana / MinIO / Vault UI / store UIs (up) | domain OK |
| Argo / Headlamp / Lago / Langfuse / Temporal / LiteLLM / n8n / … | leave `[ ]` |

Phase tests: discovery + no Authentik ticked in [tests/phase-1.md](tests/phase-1.md). Login/role boxes remain open.
