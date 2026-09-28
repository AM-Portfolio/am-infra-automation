# DR — Phase 2 (infra / Edge / stores / seed)

Skill: `phase-2-infra.md` · tests `tests/phase-2.md` (2A–2I) · sizing: [SIZING.md](SIZING.md).

Run **on VPS3** as `am-ops` / G1 for Kind. Access **off**. State: `/data/am-state/terraform/dr/`.  
**Host:** 8c / 32 GB / 500 SSD · all Kind **1-node** · `environment=dr`.

```text
2A Kind → 2B Edge → 2C Exposer+DNS → 2D Stores+Vault → 2E IngressRoutes
  → 2F Pre-seed domain Test → 2G Seed → 2H Post-seed → 2I Grown
```

## Prereq

Phase 1 + 5.1 green. Credentials: `~/.asrax/credentials.d/dr.env` (domain URLs).  
Read [SIZING.md](SIZING.md). Prod must stay healthy on VPS1.

## Implement

### 2A — Kind

- [x] Confirm host **8 vCPU · 32 GB**.
- [x] G1 / TF: `am-dr-infra` :6443 · `am-dr-apps` :6444 · `am-dr-platform` :6445 (all `one`) — inventory if already created.
- [x] kubeconfig SoT `/data/am-state/kubeconfig.am-dr-{infra,apps,platform}.yaml` · laptop `~/.asrax/kubeconfig.am-dr-*.yaml`.
- [x] Nodes Ready.

### 2B — Edge (before stores)

- [x] `init-backend` + terraform apply edge on VPS3 (Traefik + cloudflared).
- [ ] Tunnel `asrax-dr-tunnel` healthy; origin **only** Traefik.
- [ ] Proxied CNAMEs → tunnel for HTTPS store UIs (`*-dr.asrax.in`).

### 2C — Exposer + DNS-only TCP

- [x] Apply exposer: target `am-dr-infra-control-plane` via Docker DNS — **no** Kind bridge IP.
- [x] DNS-only A: `postgres-dr` / `mongodb-dr` / `redis-dr` / `kafka-dr`.asrax.in → VPS3 public IP (grey cloud).

### 2D — Stores + Vault

- [x] Apply stores with **`environment=dr`** sizing.
- [x] PostgreSQL, MongoDB, Redis, Kafka, Influx, MinIO, Vault (`injector.enabled=false`, `enable_watcher=true`).
- [x] Vault: KV `apps`, policy `am-apps-read`, `vault-unseal-keys` from `vault-dr-infra.json`.
- [x] Create PG/Mongo `platform` + users **before** seed.
- [x] Console pods: pgAdmin, mongo-express, kafka-ui, redis-commander.

### 2E — IngressRoutes

- [x] `enable_gateway=true`; IngressRoutes for Vault/MinIO/S3/Influx/Traefik/consoles — `*-dr` hosts.

## Test — 2A–2E

- [ ] Kind `am-dr-infra` up.
- [ ] Traefik Ready; cloudflared Ready; tunnel healthy.
- [ ] Exposer uses Docker DNS hostname.
- [ ] All store pods Ready; Vault watcher Running; injector off.

### HTTPS CNAME inventory (`*-dr`)

| HTTPS host | Expected |
|------------|----------|
| `vault-dr.asrax.in` | health 200 |
| `minio-dr.asrax.in` / `s3-dr.asrax.in` | live 200 |
| `influxdb-dr.asrax.in` | health 200 |
| `traefik-dr.asrax.in` | api 200 |
| store consoles `*-dr` | 200/302 |

### TCP DNS-only

| TCP host | Port |
|----------|------|
| `postgres-dr.asrax.in` | 5432 |
| `mongodb-dr.asrax.in` | 27017 |
| `redis-dr.asrax.in` | 6379 |
| `kafka-dr.asrax.in` | 9092 |

## Test — 2F Pre-seed (hard gate)

- [x] Domain tests only (G27) — Traefik / Vault / MinIO / Influx / consoles / TCP stores.
- [x] Grep fail: localhost / port-forward.
- [x] **GATE 2F green — do not seed until checked.**

## Implement + Test — 2G Seed

- [x] Restore postgres / mongodb / redis from R2 `disaster/latest` via `*-dr` domains. *(Kind pack via VPS1 mirror `/data/am-state/seed/disaster-latest`)*
- [x] Influx: TF + sync script — **not** R2.
- [x] Did **not** use laptop folder as seed SoT.

## Test — 2H Post-seed / Grown 2I

- [x] PG/Mongo/Redis seed visible via domain; Vault/MinIO/Kafka still OK. *(Keycloak `user_entity`=5; mongo market_data/portfolio present; Redis PING)*
- [x] Replay 2F+2H green; Access still off; ready for Phase 3.

## Stop if fail / Refuse

Never: stores before Edge; port-forward Test; Influx from R2; bake exposer IP; Access mid Phase 2.
