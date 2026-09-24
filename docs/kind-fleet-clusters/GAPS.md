# GAPS — kind-fleet-clusters

Single list of holes and the **fastest unblock**.  
Plan: [PLAN.md](PLAN.md) · Checklist: [TODO.md](TODO.md)

**Sync is not dumps.** VPS1 Postgres = primary, VPS3 = streaming standby. Mongo = replica set (VPS1 primary, VPS3 secondary). R2 dumps = **both-VPS-dead** backup only.

| Count | Status |
|-------|--------|
| Blockers G1–G5, G7, G15, G19–**G28** | **Locked** |
| Majors | G6, G8–G12 cheap or Execute |
| Minors | G13, G16, G17 (Kafka) accepted |

Overall: **8.6 / 10**. Unplanned VPS1 death ~8.5 if replica lag is seconds. Scale: **~10k / 6 months**, VPS3 ≥ 32 GB. Grafana/obs on VPS2.

---

## Fast unblock

```text
0 Phase P: local + VPS SSH + Cloudflare MCP (zone/tunnels/R2)
1 daily R2 disaster dump + laptop pull
2 Phase C CLEAN four hosts (prod down until rebuilt)
   local: kind delete k8s in Docker only
   VPS1/2/3: kind delete + docker prune, free disk
3 Phase 1 TF module (`am-<env>-<role>` / `am-obs`; never `am-preprod` / `am-local`)
4 FOUR TRACKS TOGETHER: dev + prod + dr + ops
5 G20 when prod+dr infra exist; CF LB
6 later: promote/failback as before
```

**G21:** Clean is scoped. Local must not wipe `~/.asrax` or Docker engine. VPS must not skip Phase 0.

---

## All gaps

| ID | Sev | Gap | Symptom if ignored | Fix (locked) | Phase |
|----|-----|-----|--------------------|--------------|-------|
| G1 | Blocker | `am-ops` cannot create/wipe Kind | DR never stands up | Break-glass: `kind create\|delete`, `docker stop\|start` Kind, `cloudflared`, **`pg_ctl promote`**, **Mongo `rs.stepUp`** | 5, 6, 7, 8 |
| G2 | Blocker | Fence is tunnel-only | Two writers | Stop VPS1 Kind (or host dead). **Promote** VPS3 PG + Mongo. One writer | 7 |
| G3 | Blocker | VPS3 undersized | DR dies mid-rebuild | VPS3 ≥ 32 GB. R2 laptop pull before wipe (disaster only) | 5.3, 7 |
| G4 | Blocker | Apps still call Contabo / localhost | Wrong store / leak | After seed: **DNS-only `*.asrax.in`** → host/WG IP. Never localhost / docker host / orange-cloud | 2, 6 |
| G5 | Blocker | No offsite copy if both VPS die | Replica gone with both hosts | **Daily** R2 dump (PG+Mongo+Vault+MinIO+PKI+tfstate). **Not** used to sync DR | 0 |
| G6 | Major | Host-port mesh unspecified | Kafka/Vault CSI fail | Published-port table. Gate: produce + Vault read | 2, 6 |
| G7 | Blocker | Traffic stays on dead VPS1 | Downtime until human | Warm DR + CF LB failover. No auto-failback | 6, 12 |
| G8 | Major | MCP env lock checkbox | Prod write from local kube | `dev.env` vs `prod.env` vs `dr.env` | 2, 6 |
| G9 | Major | Grafana dark on fence | Blind rebuild | Move Grafana to VPS2 before Phase 7 if VPS2 exists | 11 |
| G10 | Major | Failures draw.io stale | Diagram ≠ PLAN | Host remap done (VPS2 obs / VPS3 DR). Rest on Execute | Execute |
| G11 | Major | Single-node DR weaker | OOM under 10k | Size VPS3; no fourth VPS | 5.3 |
| G12 | Minor | n/a | — | Cross-store dump skew obsolete for PG/Mongo (replica) | — |
| G13 | Minor | One Keycloak / tunnel | Login dies with box | Move `auth` with `am` | 7 |
| G14 | **Replaced by G20** | 2 min dump too slow | Login missing on DR | **Realtime PG WAL + Mongo oplog.** Dump cadence retired for sync | 6 |
| G15 | Blocker | Re-login on failover | Password screen | JWT + same issuer + same realm keys via **live PG standby**. JWKS not Redis | 6, 12 |
| G16 | Minor | Argo prune false | Leftovers | Accepted | 6 |
| G17 | Minor | Kafka in-flight lost | Bus events drop | Accepted. No Kafka replica this pack | 7 |
| G18 | **Replaced by G20** | Restore cron overwrites DR | Wipes live writes | **No restore-from-R2 onto PG/Mongo.** Promote only. R2 restore = disaster or empty rebuild | 7 |
| G19 | Blocker | No page / no quotes | Frozen market | Shell + live `am-market-data` → broker. Health includes UI + market | 6, 12 |
| G20 | Blocker | Dump sync not realtime | Login 2 min ago missing | **Postgres primary/standby + Mongo replica set** over WireGuard. Promote on failover | 5.3, 6, 7 |
| G21 | Blocker | Clean wipes the wrong thing | Lost `~/.asrax` or dump | Local = Kind/k8s in Docker only. VPS Kind+prune **after** Phase 0. Then four tracks together | C |
| G22 | Blocker | Empty DBs after stand-up | No Keycloak users / no market history | After **domain Test (before seed)** is green, seed from **`asrax-db-backups`**. Then Test again on domain. Then G20 | 2 |
| G23 | Blocker | Blind-copy preprod Vault values | Local/prod still call `*-preprod.asrax.in` | Copy **key names only**. Rewrite host/JDBC/issuer/redirect. Phase **4a–4g** waves via am-gitops (identity before market; Postman MCP closout) | 4 |
| G24 | Blocker | Consoles missing / no OIDC / no domain | Operators use raw ports; wrong issuer | All UIs on env domain + Keycloak after Vault rewrite. oauth2-proxy if no native OIDC | 4 |
| G25 | Blocker | No cluster SA / auth for Vault | Apps cannot read secrets; people add a sidecar | **`am-backend-sa` + CSI** on apps cluster. Vault `auth/kubernetes-apps` against that cluster’s API. **No injector pod** | 4 |
| G26 | Blocker | Access via localhost / Docker host | Wrong env; CSI/OIDC break | After DBs exist: **domain only**. Grep fail `localhost` / `127.0.0.1` / `host.docker.internal` | 2+ |
| G27 | Blocker | Test via port-forward / skip pre-seed domain test | Seed onto unreachable DBs; false green | **No port-forward.** Domain-test every store **before** seed, then seed, then domain-test again | 2+ |
| G28 | Blocker | Clean / domains before connections | Wipe with no SSH; CF tunnel fails in Phase 4 | **Phase P first:** local + VPS SSH + Cloudflare MCP (zone, tunnels, R2). Then dump. Then clean | P |

---

## G20 — Postgres primary/standby + Mongo replica

```text
VPS1 PG  PRIMARY   --WAL / WireGuard-->  VPS3 PG  STANDBY
VPS1 Mongo PRIMARY --oplog / WireGuard-->  VPS3 Mongo SECONDARY
```

- Private link only (WireGuard or tailscale). **Do not** publish `:5432` / `:27017` on the public internet.
- Apps on each host still use `127.0.0.1` (G4). Replication bind = WG address.
- One writer. After failover: `pg_ctl promote` + `rs.stepUp` on VPS3 (G1 allowlist).
- VPS1 returns as **new standby / secondary** and catches up. Human then sets CF primary back.
- Keycloak + Temporal + app DBs are on that one Postgres, so a login 2 seconds ago is on VPS3.
- Positions/orders: Mongo secondary is live (seconds), not a 5 min dump.

**R2:** daily (or on-demand) dump from the **current primary** for “both boxes dead.” Never apply that dump onto a running replica.

---

## G1 — Kind + promote break-glass

Allowlist root: `kind create|delete`, `docker stop|start` Kind nodes, `systemctl stop|start cloudflared`, `pg_ctl promote` (or kubectl exec equivalent), Mongo `rs.stepUp`. Log `/var/log/am-break-glass.log`.

### G2 / G7 — Failover

Unplanned: host dead → no VPS1 writers; CF health fails; promote VPS3 if standby is still read-only.  
Planned: stop VPS1 Kind → promote VPS3 → CF already failing over.  
Grey (sick but writing): stop VPS1 Kind first, then promote.

### G15 — JWT

Same as before, but Keycloak keys/sessions arrive via **PG streaming**, not a dump. Access JWT on device still works immediately; refresh rows are already on the standby.

### G19 — Page + live market

Unchanged: shell + broker quotes. Positions/orders now **live** via Mongo replica (G20).

### G4 — DSN (domain in config, private under the name)

| Store | Name in Vault / apps | Resolves to | Replication |
|-------|----------------------|-------------|-------------|
| Postgres | `postgres-<env>.asrax.in` | host private IP (DNS-only) | WG IP only |
| Mongo | `mongo-<env>.asrax.in` | same | WG IP only |
| Redis / Kafka / Vault / MinIO / Influx | matching `*-<env>.asrax.in` | same | no RS this pack |

Never write `localhost`, `127.0.0.1`, `host.docker.internal`, or a Docker-host IP into Vault or Helm. Do not orange-cloud DB records. Prove UIs: `am-dr.asrax.in` / `auth-dr.asrax.in`.

### G5 — Disaster dump only

Daily on the **primary**: PG + Mongo + Vault + MinIO + PKI + tfstate → R2. Laptop pull before a wipe. Not the DR sync path.

---

### G22 — Seed after domain Test (before seed)

`F:\am-repos\asrax-db-backups\{postgres,mongodb,redis,influx}\{kind,prod,shared,preprod}\latest` + `BACKUP_OK.txt`. Restore **only after** Phase 2 **Test (before seed)** is green on domain (G27). Then Test (after seed) on the same domains. Then G20. Not the day-2 sync path.

### G23 — Vault keys only + domain rewrite

Reference paths (not values): [values.preprod.yaml](../../../am-market/am-market-data/helm/values.preprod.yaml) — `apps/data/preprod/infra/postgres|mongodb|redis|kafka|influxdb|observability` and `apps/data/preprod/services/<service>` (start with market-data, identity, gateway; expand per 4c–4g).

Write `apps/data/<env>/…` with the **same key names**. For each value: read preprod, **do not paste it**. Hosts, JDBC/Mongo URIs, Keycloak issuer, OAuth redirect, Kafka advertised listeners, MinIO endpoint → this env’s domain (`*-dev.asrax.in` / prod / `*-dr.asrax.in`). Passwords: new Kind + restored dump, not leftover preprod hostnames.

Deploy via **am-gitops** waves (TODO Phase **4a–4g**): Vault/G25 → gitops retarget (+ create missing `dr/`) → gateway/UI → identity+token → market → portfolio/trade/doc → remaining → **Postman MCP** closout. Do **not** stop after market-data.

### G24 — All UIs on domain + OIDC

After Vault rewrite, publish and log in:

modern-ui, gateway, Keycloak, MinIO, Grafana, Argo CD, **Headlamp**, **Kafka UI**, **pgAdmin**, Mongo Express, Redis UI, Vault UI, Influx UI, Temporal Web, **Lago**, Traefik dashboard.

OIDC client or oauth2-proxy → `am-realm`. Same roles. Then continue Phase **4c–4g** (gateway/UI → identity → market → remaining + Postman MCP). Do not halt after market-data.

### G25 — Cluster Vault access (no sidecar)

Working preprod pattern: [VAULT_ONBOARDING_GUIDE](../../../am-infra/docs/VAULT_ONBOARDING_GUIDE.md). Helm default: `global.vault.serviceAccountName: am-backend-sa`, role `am-backend-role` ([values.yaml](../../../am-market/am-market-data/helm/values.yaml)).

Apps and Vault are **different Kind clusters**. Infra Vault cannot review an apps-cluster JWT unless a **separate k8s auth mount** points at the apps API.

```text
am-dev-apps  CSI DaemonSet  --127.0.0.1:8200-->  Vault on am-dev-infra
pod uses SA am-backend-sa
Vault auth/kubernetes-apps reviews token via apps API :6444
```

| Piece | Where | What |
|-------|-------|------|
| CSI Secrets Store + vault-csi-provider | **apps** cluster | DaemonSet, one per node. Not a container on the app pod |
| `am-backend-sa` | `am-apps-<env>` | `automountServiceAccountToken: true`. `regcred` / `github-registry-secret` |
| `vault-auth-reviewer` | apps `kube-system` | `system:auth-delegator` — Vault uses this JWT to TokenReview |
| `auth/kubernetes-apps` | Vault on infra | `kubernetes_host=https://127.0.0.1:6444` (that host’s apps API) |
| `am-backend-role` | same mount | `bound_service_account_names=am-backend-sa`, `bound_service_account_namespaces=am-apps-dev\|am-apps-prod\|am-apps-dr` |
| Policy `am-apps-read` | Vault | `read,list` on `apps/data/<env>/*` |

**Do not** enable Vault Agent Injector (`injector.enabled=false`). **Do not** put a Vault sidecar / “mini pod” on `am-market-data`. Helm: `global.vault.csi.enabled=true`.

Same SA + mount pattern on prod/dr apps clusters (API 6444 on that host).

### G26 — Domain only after DBs exist

Stated **once**. From the moment store DNS exists, humans, MCP, Vault values, OIDC, Kafka advertised listeners, and CSI Vault addr use **`https://…asrax.in`**. Never `localhost`, never Docker host. Each later phase **Test (grown)** re-checks this grep.

### G27 — Restrict tests (no port-forward)

Always:

1. Prove stores and UIs on the **env domain** only.
2. **Forbidden:** `kubectl port-forward`, `localhost`, Docker host, raw NodePort as a Test.
3. Phase 2: domain-test **all** DBs (PG, Mongo, Redis, Kafka, Influx, MinIO, Vault) **before** any restore. Seed only if that list is green. Domain-test again after seed.

Later phases inherit this in **Test (grown)**.

### G28 — Connections before clean

Phase P must pass before dump-as-wipe-prep and Phase C. Connection source: [VPS/.env](../../../VPS/.env) keys `VPS_IP` / `VPS_2_IP` / `VPS_3_IP` (never passwords/tokens in the pack). Start and test: laptop local/dev Docker, SSH all three VPS, Cloudflare MCP zone + tunnels + R2. Same MCP is reused later for DNS, G24, and the **gateway** tunnel. Do not clean if any of those tests fail. Legacy `VAULT_ADDR=localhost:8201` in that file is not the new Vault URL.

## What we will not do

Cilium mesh, fourth VPS, **auto-failback**, Kafka replica, Redis-as-session, public PG/Mongo, wipe Contabo while it is the healthy primary, restore R2 onto a live replica, **copy preprod Vault values as-is**, **Vault Agent Injector sidecar on app pods**, **access via localhost or Docker host after seed**, **`kubectl port-forward` as a test**, **seed before domain Test is green**, **deploy a second AM service in this pack**.
