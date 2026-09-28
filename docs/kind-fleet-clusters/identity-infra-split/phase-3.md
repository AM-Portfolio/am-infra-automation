# Phase 3 — Prove prod apps + am-identity

**Goal:** Prod services on `am-prod-apps` work against infra Keycloak + **same** Contabo DB stack + Vault `prod/…`.

**Prereq:** [phase-1.md](phase-1.md) + [phase-2.md](phase-2.md) green.

## Implement

- [x] Vault seed / rewrite if Issuer URLs moved (`apps-vault-seed` / mappings) — issuer still `https://auth.asrax.in/realms/am-realm`
- [x] Confirm am-identity + gateway → `auth.asrax.in` and Vault `prod` paths
- [x] Smoke: login; one market or portfolio call
- [x] G26 domains only (`am.asrax.in`, …) — no port-forward as Test
- [ ] GitOps: no leftover platform-Kind Keycloak URLs *(spot-check remaining)*

## Test

Use [tests/phase-3.md](tests/phase-3.md).

- [x] Login via am-identity *(OIDC password-grant + `/identity/health` 200)*
- [x] One market **or** portfolio authenticated call *(`/market/.../quotes` 200 with bearer)*
- [x] Apps still on `am-prod-apps`; stores on infra
- [x] Grown: auth + stores + platform-on-infra green

## Grown

- [x] Contabo Phases 1–3 green → unlock Phase 4 nonprod / Phase 6 DR prep
- [x] Still 2 Kind + 1 DB stack

## Stop if fail

Login/API fail → fix Vault/OIDC; do not start preprod delete or CF cutover.

## Refuse

- Contabo wipe; apps → other-VPS Keycloak; DR promote; second Vault
