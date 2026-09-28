# Phase 2 — Major consoles OIDC

**Goal:** Browser SSO for Argo, Vault UI, Headlamp, Lago, Langfuse, Temporal, LiteLLM, Grafana, MinIO, and remaining [CONSOLE_MATRIX.md](CONSOLE_MATRIX.md) rows.

**Prereq:** Phase 1 Test + Grown green.

## Implement

- [x] Argo CD OIDC → Keycloak; RBAC groups `am-admin` admin / `am-ops`+`am-viewer` readonly
- [x] Vault UI OIDC → Keycloak `vault-ui`; role policies (CSI for pods unchanged) — `modules/apps/vault/oidc.tf` + stores `oidc_*` vars
- [x] Headlamp fleet module: enable OIDC; IngressRoute domain — `kind-fleet/prod/platform/iam-sso.tf`
- [x] Lago / Langfuse / Temporal Web / LiteLLM: oauth2-proxy wrappers (platform `iam-sso.tf`)
- [x] Grafana (fleet + VPS2 Compose) → `https://auth.asrax.in/realms/am-realm` (`compose/obs/secrets/grafana.env.example`)
- [x] MinIO: Keycloak discovery URL (not Authentik path); stores enable when secret passed
- [x] oauth2-proxy module for UIs without native OIDC (Kafka UI, pgAdmin, mongo-express, redis-ui)
- [x] Update CONSOLE_MATRIX `phase_wired` = 2 for wired rows
- [ ] Operator: re-apply platform + stores with `oidc_client_secrets` from Vault KV

## Test

Use [tests/phase-2.md](tests/phase-2.md).

## Grown

- [ ] Phase 1 token claims still present
- [ ] Product modern-ui login still works

## Stop if fail

Leave break-glass local admin passwords in Vault only; do not re-enable Authentik.

## Refuse

- No port-forward Test greens
- No localhost OIDC redirects for fleet consoles
