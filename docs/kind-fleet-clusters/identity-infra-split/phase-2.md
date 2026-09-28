# Phase 2 — Platform tools on infra (retire third Kind)

**Goal:** Argo / Temporal / Lago / n8n / … run as NS on **am-prod-infra** (same DB stack). Retire `am-prod-platform` after soak. Free :6445.

**Prereq:** [phase-1.md](phase-1.md) green.

## Implement

- [x] Point `terraform/kind-fleet/prod/platform` providers at infra kubeconfig (`kind-am-prod-infra`) via **TF** — see [TF-OUTLINE.md](TF-OUTLINE.md); `terraform apply` (no surgery script)
- [x] Deploy/move platform tools → **infra** cluster; JDBC/URLs → Contabo infra stores only
- [x] Lago stays **prod only** — DB `lago` on same infra PG
- [x] After soak: Keycloak on infra; `am-prod-platform` Kind destroyed (`co_locate_on_infra=true`)
- [x] Confirm no new Kind create for platform; port **6445** unused
- [x] Retire Traefik bridges that only existed for cross-cluster platform (TF/IngressRoute)

## Test

Use [tests/phase-2.md](tests/phase-2.md).

- [x] Argo / Temporal / Lago HTTPS (G26) OK
- [x] Platform tool pods on **infra** context (not `kind-am-prod-platform`)
- [x] After retire: `am-prod-platform` gone or documented drained
- [x] `auth.asrax.in` still green
- [x] Still **one** store stack (no second STS)

## Grown

- [x] Contabo = **2** Kind only
- [x] Platform = NS on infra; IdP = infra
- [x] Ready for Phase 3 apps prove

## Stop if fail

Tools break after move → fix on infra before Kind delete of old platform.

## Refuse

- New `am-prod-platform` Kind
- Full preprod platform on Contabo
- Lago on nonprod in this phase
- Second Contabo DB stack
- Surgery scripts instead of `terraform apply` for the platform move
