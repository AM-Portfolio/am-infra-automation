# DR — Phase 6 (G20 replica + Cloudflare LB) — DR primary

Skill: `phase-6-12.md` · tests `tests/phase-6-12.md` · Data: skill `backup-dr-data.md` · CF: `cloudflare-tf.md`.  
**SoT:** [FAILOVER.md](../identity-infra-split/FAILOVER.md) — **DR first, Contabo fallback** (inverted from older Contabo-primary drafts).  
Writer endpoints: [g20-dr-writer.md](g20-dr-writer.md).

## Prereq

Phase 5 Argo closout green. Phase 5.3 WireGuard up. DR edge healthy (`asrax-dr-tunnel`, Traefik, bare + `*-dr` Host matches). Contabo warm. Prod `/health` green as fallback.

## Implement

### G20 — streaming replica (DR preferred writer)

- [ ] **Steady state:** Postgres **primary on VPS3 (DR)**; Contabo is **standby** over WG `:5432` (or Contabo remains sync-ready promote target).
- [ ] **Steady state:** Mongo **primary on VPS3**; Contabo **secondary** over WG `:27017`.
- [ ] Lag measured in **seconds**. **No** dual writer.
- [ ] On fall-to-Contabo: promote Contabo (`pg_ctl promote` / `rs.stepUp`), fence DR writers.
- [ ] On restore-to-DR: catch up DR, promote DR, demote Contabo — human gated with CF `dr_pool_enabled`.
- [ ] **No** R2 restore cron onto live PG/Mongo replica.

### Cloudflare LB

Stack: [`terraform/kind-fleet/prod/cloudflare-lb/`](../../../terraform/kind-fleet/prod/cloudflare-lb/).

- [ ] Enable CF **Load Balancing** subscription on the account (required).
- [ ] Terraform: monitors + pools; `default_pool` = **DR**, `fallback_pool` = **Contabo**; all proxied bare HTTPS hosts from prod edge.
- [ ] Health: UI `/health`, Keycloak `/realms/master`, Vault `/v1/sys/health`; interval/retries tuned for RTO.
- [ ] **Auto-failback off** via `dr_pool_enabled=false` after Contabo fallback + notification.
- [ ] Confirm `*-dr.asrax.in` still direct to DR tunnel for warm drills.

### Isolation

- [ ] No dual writer while both sites up.
- [ ] Contabo takes writes **only** after DR failure + promote.

## Test

- [ ] Replica lag seconds (PG + Mongo) with DR as preferred writer.
- [ ] Every G24 **DR** host on `*-dr.asrax.in` still OK.
- [ ] G19: `https://am-dr.asrax.in` shell + live quotes.
- [ ] Bare `https://am.asrax.in` / `auth` / `vault` served from DR while pools healthy.
- [ ] Drill: stop DR Kind or cut VPS3 → bare hosts land on Contabo **without DNS edit** (once LB live); time RTO; set `dr_pool_enabled=false`; human restore DR.
- [ ] G25: no Vault sidecar on DR AM pods (spot-check).

## Grown

- [ ] Phase 5.3 WG still up.
- [ ] Phase 0 dump still on laptop / R2 from current writer.
- [ ] Notification wired for fall-to-Contabo.
- [ ] Warm Contabo fallback complete — Phase 7+ only on separate Execute.

## Stop if fail / Refuse

No R2 restore onto live replica. No CF auto-failback. No dual writer. No silent Contabo retarget without promote. Confirm before flipping G20 writer or enabling LB traffic.
