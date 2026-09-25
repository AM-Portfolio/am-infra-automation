# Prod — Phase 2 (infra / Edge / stores / seed)

Skill: `phase-2-infra.md` · tests `tests/phase-2.md` (2A–2I) · seed: skill `backup-dr-data.md` · CF: skill `cloudflare-tf.md` · sizing: [SIZING.md](SIZING.md).

Run **on VPS1** as `am-ops` / G1 for Kind. Access **off**. State: `/data/am-state/terraform/prod/`.  
**Current host:** 8c / 64 GB / 500 SSD · infra Kind **2-node** · `environment=prod`.

```text
2A Kind → 2B Edge → 2C Exposer+DNS → 2D Stores+Vault → 2E IngressRoutes
  → 2F Pre-seed domain Test → 2G Seed → 2H Post-seed → 2I Grown
```

## Prereq

Phase 1 + 5.1 green. Credentials: `~/.asrax/credentials.d/prod.env` (domain URLs).  
Read [SIZING.md](SIZING.md) — stand up on **current** class; shrink to 6c/36GB is a **later** cutover.

## Implement

### 2A — Kind

- [x] Confirm host still **8 vCPU · 64 GB** (if already on 6/36, stop — follow target path in SIZING.md first). (VPS1: 16 vCPU / 61 Gi available — serve-first OK.)
- [x] TF apply (root): `am-prod-infra` API **:6443** (**2-node** / `node_shape=two`). Also created `am-prod-apps` :6444 / `am-prod-platform` :6445 early for kubeconfig inventory.
- [x] kubeconfig SoT `/data/am-state/kubeconfig.am-prod-{infra,apps,platform}.yaml` · am-ops `~/.asrax/` · laptop `~/.asrax/kubeconfig.am-prod-*.yaml` (server = VPS1 public IP).
- [x] Nodes Ready (infra control-plane + worker; apps/platform control-plane).

### 2B — Edge (before stores)

- [x] `init-backend` + terraform apply edge on VPS1 (Traefik + cloudflared).
- [x] Tunnel `asrax-prod-tunnel` healthy; origin **only** `http://traefik.infra.svc.cluster.local:80` (+ 404 catch-all).
- [x] Proxied CNAMEs → tunnel for HTTPS store UIs (TF). Fixed conflicting `influx` A→CNAME.

## Test notes (2B)

- Traefik + cloudflared Ready; `https://traefik.asrax.in/api/version` → 200.
- Deleted leftover DNS-only A `influx.asrax.in` → `203.174.22.129` so TF CNAME could apply.

### 2C — Exposer + DNS-only TCP

- [x] Apply exposer: target `am-prod-infra-control-plane` via Docker DNS — **no** `172.19.x`.
- [x] DNS-only A: `postgres` / `mongo` / `redis` / `kafka`.asrax.in → `203.174.22.129` (grey cloud). Fixed `mongo` (was orange CNAME).

### 2D — Stores + Vault

- [x] Apply stores with **`environment=prod`** sizing (full prod requests/limits/disks).
- [x] Apply stores: PostgreSQL, MongoDB, Redis, Kafka, Influx, MinIO, Vault (`injector.enabled=false`).
- [x] Vault: KV `apps`, policy `am-apps-read`, `vault-unseal-keys`, watcher on / unsealer off.
- [x] Create PG/Mongo `platform` + users (keycloak, temporal, lago, n8n, …) **before** seed.
- [x] Console pods: pgAdmin, mongo-express, kafka-ui, redis-commander.
- [x] Spot-check pod requests fit **64 GB** host (leave OS/Docker/Kind headroom).

### 2E — IngressRoutes

- [x] `enable_gateway=true`; IngressRoutes for Vault/MinIO/S3/Influx/Traefik/consoles — bare prod hosts.

## Test — 2A / 2B / 2C / 2D / 2E

- [x] Kind `am-prod-infra` up; context usable.
- [x] Traefik Ready; cloudflared Ready.
- [x] Cloudflare MCP: tunnel `asrax-prod-tunnel` healthy; each hostname → Traefik + 404 catch-all.
- [x] Exposer uses Docker DNS hostname (no bridge IP). Fixed socat **TCP4**; target **`am-prod-infra-worker`** (CP mongo NodePort :30017 timed out).
- [x] All store pods Ready; Vault watcher Running; injector off. MinIO via `am-local/minio` + `am-local/mc` (Quay 401).

### HTTPS CNAME inventory (bare prod)

| HTTPS host | CNAME→tunnel | Result |
|------------|--------------|--------|
| `vault.asrax.in` | `68770b3c-…cfargotunnel.com` | 200 `/v1/sys/health` |
| `minio.asrax.in` | same | 200 `/minio/health/live` |
| `s3.asrax.in` | same | 200 `/minio/health/live` |
| `influx.asrax.in` | same | 200 `/health` |
| `traefik.asrax.in` | same | 200 `/api/version` |
| `pgadmin.asrax.in` | same | 302 |
| `mongo-express.asrax.in` | same | 200 |
| `kafka-ui.asrax.in` | same | 200 |
| `redis-ui.asrax.in` | same | 200 |

### TCP DNS-only

| TCP host | Private IP | Port | Result |
|----------|------------|------|--------|
| `postgres.asrax.in` | 203.174.22.129 | 5432 | SELECT 1 OK |
| `mongo.asrax.in` | 203.174.22.129 | 27017 | ping OK (exposer → worker NodePort) |
| `redis.asrax.in` | 203.174.22.129 | 6379 | PING OK |
| `kafka.asrax.in` | 203.174.22.129 | 9092 | TCP OK; EXTERNAL=`kafka.asrax.in:9092` |

- [x] Kafka `advertised.listeners` EXTERNAL = `kafka.asrax.in:9092`.

## Test — 2F Pre-seed (hard gate)

| Check | How | Result |
|-------|-----|--------|
| Traefik | `https://traefik.asrax.in` `/api/version` or dashboard | 200 |
| Vault | status/KV via `https://vault.asrax.in` (MCP preferred) | health 200; KV `apps/` + `am-apps-read` |
| MinIO | `https://minio.asrax.in` or s3 health/live | 200 |
| Influx | `https://influx.asrax.in/health` | 200 |
| Consoles | pgAdmin / mongo-express / kafka-ui / redis-ui domain | 302/200 |
| Postgres | `SELECT 1` via `postgres.asrax.in` | OK |
| Mongo | ping via `mongo.asrax.in` | OK |
| Redis | PING via `redis.asrax.in` | OK |
| Kafka | list_topics via `kafka.asrax.in` | TCP connect OK |

- [x] Grep fail: localhost / port-forward / host.docker.internal (domain Test only; 127.0.0.1 docker-proxy flaky — use domains).
- [x] Store UIs without Access cookie.
- [x] **GATE 2F green — do not seed until checked.**

## Implement + Test — 2G Seed

- [x] Restore postgres from R2 `disaster/latest` via `postgres.asrax.in`.
- [x] Restore mongodb from R2 via `mongo.asrax.in`.
- [x] Restore redis from R2 via `redis.asrax.in`.
- [x] Influx: TF already applied — **not** R2 (`sync-influx-vps.ps1` N/A single-VPS stand-up).
- [x] Did **not** use laptop folder as seed SoT (R2 mirror pack `asrax-disaster-r2` ↔ MCP-listed R2 keys).

## Test — 2H Post-seed

- [x] PG `platform` roles still exist; seed sample visible via domain (Keycloak `user_entity`=5).
- [x] Mongo portfolio/market_data seed sample visible.
- [x] Redis PING OK (DBSIZE=0 TTL-expired dump — same as kind).
- [x] Influx health via `https://influx.asrax.in`.
- [x] Vault / MinIO / Kafka still on **same** domains.
- [x] Consoles still domain-OK; grep fail still clean.

## Grown — 2I

- [x] Replay 2F + 2H still green.
- [x] Tunnel Traefik-only; Access still off; watcher Running.
- [x] R2 disaster objects not wiped.
- [x] Ready for Phase 3.

## Stop if fail / Refuse

| Fail | Action |
|------|--------|
| 2A–2E | Fix; no seed |
| 2F | **Do not seed** |
| 2G–2H | Fix; no Phase 3 |

Never: stores before Edge; port-forward Test; Influx from R2; bake exposer IP; Access mid Phase 2; `kind delete` for seal/SSL EOF.  
Do not shrink to **6c/36GB** or flip infra to 1-node during this stand-up — follow [SIZING.md](SIZING.md) target cutover later.
