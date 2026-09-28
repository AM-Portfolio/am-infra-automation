# Phase 1 — Keycloak foundation

**Goal:** `am-realm` has 24h SSO sessions, four `am-*` roles, JWT claim mappers, and all console OIDC clients (incl. `kubectl`).

**Prereq:** Keycloak reachable at `https://auth.asrax.in` (identity-infra / platform Phase 3a).

## Implement

- [x] `configure_realm.py`: set SSO Session Max/Idle ≈ 24h; access token lifespan ≈ 1h; client session max ≈ 24h
- [x] Protocol mappers: realm roles → `roles` (Grafana) and `groups` (Argo / Kubernetes)
- [x] `realm_roles` default = `am-admin`, `am-ops`, `am-viewer`, `am-user` only
- [x] Add OIDC client `kubectl` (oidc-login redirect URIs)
- [x] Align `test_users.tf` with `am-*` roles
- [ ] Re-apply Keycloak TF / re-run realm configure on target env (operator apply)

## Test

Use [tests/phase-1.md](tests/phase-1.md).

## Grown

- [ ] Prior Keycloak domain discovery still green
- [x] Ready for Phase 2 console wiring

## Stop if fail

Do not disable existing product OIDC clients. Roll back script only.

## Refuse

- No Authentik realm
- No committing client secrets
