# Prod — Phase 3 (platform / 3e)

Skill: `phase-3-platform.md` · tests `tests/phase-3.md`. Sizing: [SIZING.md](SIZING.md) — current **`environment=prod`** on 64 GB; do not use laptop sizes.

## Prereq

Phase 2 Test + grown (2I) green. Access still **off**.

## Implement

### 3a — Identity

- [x] G1: `kind create` `am-prod-platform` API **:6445**.
- [x] kubeconfig for `am-prod-platform`.
- [x] `init-backend.ps1 -Env prod -Role platform` + apply Keycloak + Argo (and sizing modules).
- [x] Keycloak realm `am-realm`; roles admin/ops/viewer/user; **no Authentik**.
- [x] Create **all** G24 OIDC clients once; redirects `https://*.asrax.in` only (bare prod hosts).
- [x] Secrets → Vault; Argo `prune: false`; enroll infra API.
- [x] Bridge `auth.asrax.in` / `argocd.asrax.in` on **existing** infra Traefik + same tunnel.
  - Note: exposer v5 store FQDN Docker aliases (kind hairpin); Keycloak realm bootstrap = bash/python NodePort (no PowerShell).

### 3b / 3c / 3d

- [x] Temporal on platform; PG via `postgres.asrax.in` (not cross-cluster `*.svc`).
- [x] Lago dedicated DB `lago` (OWNER + CREATEDB) — not schema on `platform`.
- [x] P1 UIs as scoped: n8n, GrowthBook, OpenProject, LiteLLM, Langfuse, Novu.
  - GrowthBook: Mongo user must live in **admin** DB when URI uses `authSource=admin` (platform-DB-only user fails auth).
  - n8n: GRANT CONNECT/schema on `platform` for n8n role.
  - Vendored Helm charts for n8n/GrowthBook (VPS GHCR OCI 403).

## Test — 3e matrix

- [x] `am ai sync` + `mcp-sync --ide cursor --host-launchers` when needed.
  - Cursor Keycloak MCP may still target preprod until local sync; prod verified via `https://auth.asrax.in` / NodePort admin API.
- [x] Keycloak on `https://auth.asrax.in` — realm `am-realm` readable (OIDC discovery + admin API).
- [x] Admin + user OIDC password-grant (passwords from Vault test-user path / rotated onto `apps/prod/infra/keycloak-test-users`).
  - Grants proven with client `am-modern-ui` (roles in access token). NodePort always; CF may 403 bot POSTs from VPS (error 1010) — UI GET still works.
- [x] Roles `am-admin` / `am-ops` / `am-viewer` / `am-user` present; assigned on `am-admin-test` / `am-user-test`.
- [x] Argo on `https://argocd.asrax.in` — list apps (0 until Phase 4); `prune: false` in `argocd-fleet-policy`; **am-prod-infra** enrolled (`https://203.174.22.129:6443` Successful).
- [x] Phase 2 store domains still up (postgres/mongo/redis/kafka TCP; minio/vault/influx/pgadmin/mongo-express/kafka-ui/redis-ui HTTPS).
- [x] Temporal / Lago / P1 UIs HTTPS when present (auth 302, argocd/temporal/lago/n8n/growthbook/litellm/langfuse/novu 200, openproject 302).
- [x] Cloudflare MCP: G24 platform CNAMEs present for prod (proxied → prod tunnel).
- [x] Auth reachable **without** Access cookie; Access still off.
- [x] Grep fail: localhost / port-forward (OIDC clients: no localhost redirects).

## Grown

- [x] Replay 3e still green (no new Helm for verify-only).
- [x] Access/MFA still not enforced.
- [x] Ready for Phase 4 Vault terraform (not product pods yet).

## Stop if fail / Refuse

Stay on Phase 3. No Phase 4 Vault/Argo apps. No Authentik. No re-create OIDC clients per wave. No Access enforce mid Phase 3.
