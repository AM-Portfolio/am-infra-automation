# Phase 1 tests — Keycloak on infra + Vault

**Phase:** [../phase-1.md](../phase-1.md)

## Test

- [x] OIDC discovery on `auth.asrax.in` returns JSON
- [x] Keycloak on **am-prod-infra**
- [x] PG/JDBC healthy; Vault seal state known
- [x] Store domains up; still one DB stack

## Grown

- [x] No `am-prod-platform` Kind created in this phase *(retired; Contabo = 2 Kind)*

## Evidence

Issuer URL only (no client secrets). `https://auth.asrax.in/realms/am-realm` · 2026-09-26 colocate.
