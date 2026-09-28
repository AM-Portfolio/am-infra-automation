# Phase 1 — Contabo infra + Keycloak + one Vault

**Goal:** Keycloak on **am-prod-infra**; `auth.asrax.in` → in-cluster Service; **one** Vault; **one** DB stack. No third Kind create.

**Prereq:** [phase-0.md](phase-0.md) done. Prod stores Ready ([prod/phase-2.md](../prod/phase-2.md) or equivalent).

## Implement

- [x] Confirm single store stack on Contabo (`infra` NS) — platform tools and apps will share it
- [x] Deploy Keycloak on **am-prod-infra** — JDBC: `postgres.asrax.in` / DB `platform` / schema `keycloak`
- [x] Wire Traefik: `auth.asrax.in` → Keycloak ClusterIP/Service (plan retire platform NodePort bridge)
- [x] Confirm **one** Vault; no second Vault for nonprod
- [x] Update Cloudflare / tunnel origin if KC Service port changes
- [x] Document: **do not** `kind create am-prod-platform` going forward ([TF-OUTLINE.md](TF-OUTLINE.md))
- [x] Soak: platform Kind retired; IdP = infra Keycloak (OIDC green)
- [ ] `am mcp sync` if MCP Keycloak endpoint changes

## Test

Use [tests/phase-1.md](tests/phase-1.md).

- [x] OIDC discovery `https://auth.asrax.in/realms/<realm>/.well-known/openid-configuration` (G26)
- [x] Keycloak pods on **am-prod-infra**
- [x] JDBC / PG healthy
- [x] Vault seal state known
- [x] Store domains still up (postgres, mongo, redis, …)

## Grown

- [x] `auth.asrax.in` from infra Keycloak
- [x] Single Vault + single DB stack confirmed
- [x] Ready for Phase 2 (tools on infra kubeconfig)

## Stop if fail

OIDC/JDBC fail → revert Traefik bridge; do not delete platform Keycloak yet.

## Refuse

- No platform-prod wipe / DR apply / Authentik / second Vault
- No new `am-prod-platform` Kind
- No second Contabo store STS
