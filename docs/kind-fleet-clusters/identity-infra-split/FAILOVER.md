# Failover — DR primary / Contabo fallback (CF LB + G20)

Used by [phase-6-g20-lb.md](../dr/phase-6-g20-lb.md) and [PLAN.md](../PLAN.md) G7.  
**SoT direction (locked):** **DR (VPS3)** is the live primary for all proxied HTTPS bare hosts. **Contabo (VPS1)** is warm fallback when DR or its tunnel/VPS path is down. **No auto-failback** to DR — human restores.

Automation: [TF-OUTLINE.md](TF-OUTLINE.md) — dump/sync as **Terraform-managed** CronJob/Job modules.  
CF LB stack: [`terraform/kind-fleet/prod/cloudflare-lb/`](../../../terraform/kind-fleet/prod/cloudflare-lb/).

## Team triggers (GitHub Actions — preferred)

Anyone with access to the protected Environments can flip traffic from the Actions UI (no laptop CF token).

Repo: **am-infra-automation**.

| Switch | Workflow | Input | GH Environment | Effect |
|--------|----------|-------|----------------|--------|
| Prod Contabo ↔ DR | [Edge primary](../../../.github/workflows/edge-primary.yml) | `primary=prod\|dr` | `edge-prod` / `edge-dr` | Bare CNAMEs → prod or DR tunnel |
| Preprod Contabo ↔ nonprod-dr | [Nonprod origin](../../../.github/workflows/nonprod-origin.yml) | `origin=vps\|local` | `nonprod-vps` / `nonprod-local` | KV `nonprod/origin` for Worker `am-nonprod-origin` |

### Environment secrets (am-infra-automation)

| Secret | Environments | Notes |
|--------|--------------|-------|
| `CLOUDFLARE_API_TOKEN` | `edge-prod`, `edge-dr`, `nonprod-vps`, `nonprod-local` | Required. DNS edit (edge) + Workers KV write (nonprod). |
| `CF_ACCOUNT_ID` | `nonprod-vps`, `nonprod-local` | Optional; default `23061f216225f4e2921ba51c2801874d`. |
| `CF_KV_NAMESPACE_ID` | `nonprod-vps`, `nonprod-local` | Optional; default ORIGIN_KV id from am-gitops `cloudflare/wrangler.toml`. |

Create Environments `nonprod-vps` / `nonprod-local` (and reviewers) to match `edge-prod` / `edge-dr`. Never put kubeconfig in GitHub.

Break-glass (laptop / MCP): `edge-primary.sh` / `nonprod-origin.sh` with a local token.

## Switch edge primary (until CF LB subscribed)

**Actuator:** GitHub Actions [`edge-primary.yml`](../../../.github/workflows/edge-primary.yml) → [`scripts/kind-fleet/edge-primary.sh`](../../../scripts/kind-fleet/edge-primary.sh).  
**Visibility:** GrowthBook flag `asrax_edge_primary` (`prod` | `dr`) — set to match after a switch; does **not** flip DNS by itself.

| Desired | Action |
|---------|--------|
| Contabo (day-to-day / restore) | Actions → **Edge primary** → `primary=prod` (env `edge-prod`) |
| DR (drill / outage) | Actions → **Edge primary** → `primary=dr` (env `edge-dr`) |
| Local / MCP | `CLOUDFLARE_API_TOKEN=… ./scripts/kind-fleet/edge-primary.sh prod\|dr` |

Leaves `*-dr.asrax.in` on the DR tunnel. Smoke-checks `am` / `auth` / `vault` after apply.

**2026-09-26 note:** `primary=prod` was attempted; Contabo `asrax-prod-tunnel` was **down** (0 connections) and Kind API `203.174.22.129:6443` unreachable from the ops laptop. Edge was restored to **DR** until Contabo cloudflared/Kind is healthy. Re-run workflow `primary=prod` after Contabo tunnel shows healthy in CF.

When Load Balancing is enabled, prefer `cloudflare-lb` `dr_pool_enabled` instead of raw CNAMEs; keep this workflow as break-glass.

GrowthBook: see [EDGE_PRIMARY_FLAG.md](EDGE_PRIMARY_FLAG.md) (`asrax_edge_primary`).

## Steady state (target: CF LB — DR default / Contabo fallback)

1. Cloudflare Load Balancing: `default_pool` = **DR** (`asrax-dr-tunnel`), `fallback_pool` = **Contabo** (`asrax-prod-tunnel`).
2. Bare hosts (`am.asrax.in`, `auth.asrax.in`, `vault.asrax.in`, consoles, …) attach to the LB — same URLs for users.
3. Drill hosts `*-dr.asrax.in` stay **direct CNAME → DR tunnel** (not on LB).
4. **G20:** prefer **DR as PG/Mongo writer**; Contabo is standby/replica. **One writer only.**
5. Contabo edge + apps stay warm enough to take traffic if DR dies.
6. R2 `asrax-disaster` dump continues from the **current** writer (disaster / both-boxes-dead only — never restore onto a live replica).

## When DR / VPS3 / tunnel is down

1. CF monitors fail (Kind/Traefik/tunnel/VPS path) → all LB hosts automatically use **Contabo**.
2. Notification `am-dr-pool-unhealthy-fall-to-contabo` (email) fires.
3. **Immediately** set `dr_pool_enabled = false` in `cloudflare-lb` and `terraform apply` so Contabo stays primary when DR recovers (no silent failback).
4. Promote Contabo PG/Mongo writer if DR was writer (`pg_ctl promote` / `rs.stepUp` on Contabo — see G20). Point app JDBC/Vault mappings to Contabo stores as needed.
5. Users keep the same bare URLs and credentials.

## Restore DR as primary (human)

1. Verify DR Traefik, tunnel, Keycloak, Vault, P0 apps, and G20 (DR ready to be sole writer again).
2. Replicate Contabo → DR or catch up standby; **fence** Contabo to single-writer-safe state.
3. Set `dr_pool_enabled = true` and `terraform apply`.
4. Confirm LB analytics show DR pool; smoke `am` / `auth` / `vault` bare hosts.

## Cold-start allowlist (services) — same on whichever site is live

| Priority | Component |
|----------|-----------|
| P0 edge | Traefik / gateway |
| P0 auth | Keycloak + am-identity / login |
| P0 | am-subscription |
| P0 | user-platform / user APIs |
| P0 | am-market-data |
| P0 UI | am-modern-ui + asrax-ui **minimal** |
| Later | Portfolio, trade, agents, full platform UIs, rest of apps |

## Grown after cutover / failover

- [ ] Login + one market or subscription call on **same** bare domains
- [ ] Active site stores healthy (no dependency on the dead site’s TCP)
- [ ] R2 sync lag known; G20 lag known if replica path used
- [ ] `dr_pool_enabled` matches intent (false while Contabo is emergency primary)

## Prerequisite — Cloudflare Load Balancing subscription

`asrax.in` must have **Load Balancing** enabled (paid add-on). Until then:

- Bare host CNAMEs may point **directly at the DR tunnel** as interim DR-primary (ops laptop / MCP).
- Fall-to-Contabo is a **manual** CNAME retarget to `asrax-prod-tunnel` (or enable LB and apply the TF stack).
- Terraform under `prod/cloudflare-lb` remains the SoT; `terraform apply` will fail with monitor/pool validation until LB is subscribed.

## Refuse

- Public `postgres-dr` / `auth-dr` **DB** hostnames for clients (HTTPS `*-dr` product hosts for drills are OK)
- Hydrate-only-on-outage (sync must be continuous via TF / G20)
- Bring-all-apps before P0 green
- Dual writer (DR + Contabo both accepting writes)
- Auto-return to DR when Contabo was used as fallback
- Putting Postgres/Mongo TCP on Cloudflare LB
- Laptop/dev as a pool member
