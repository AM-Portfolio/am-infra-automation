# IAM-3-DEV — Bytebase + landing

## Prereq

IAM-2 users present on Contabo stores.

## Implement

- [x] Deploy Bytebase Community on Contabo infra (`bytebase/bytebase:latest` → Running)
- [x] PG role/DB `bytebase` (DIG_PRINCIPAL_SEED derived password)
- [x] IngressRoute `bytebase.asrax.in` + `data.asrax.in`
- [x] Landing ConfigMap/nginx with inventory counts
- [x] Cloudflare tunnel ingress + DNS CNAME (same pattern as pgadmin)
- [x] Environments **Dev / Preprod / Prod** (Bytebase `ENVIRONMENT` setting)
- [x] Workspace admin **CCOT** (`ccot@asrax.in`) — password in `~/.asrax/credentials.d/bytebase-ccot.env`
- [x] Keycloak gate via **oauth2-proxy** (`oauth2-proxy-bytebase`) — Community has no native OIDC SSO
- [x] **SSO bridge** (`bytebase-sso-bridge`) — after Keycloak, auto-mints Bytebase web cookies (no second password)
- [x] Keycloak client `bytebase` + roles `access-bytebase-user` / `access-bytebase-dba`
- [x] Instances (9): pg/mongo/redis × Dev/Preprod/Prod against Contabo stores
- [x] Built-in MCP at `/mcp` — Traefik bypass (priority 9500); Marketplace → Cursor

## URLs

| UI | URL |
|----|-----|
| Landing | https://data.asrax.in |
| Bytebase | https://bytebase.asrax.in (Keycloak once → SSO bridge mints Bytebase cookies; no second password) |
| Bytebase MCP | https://bytebase.asrax.in/mcp (direct; bypasses oauth2-proxy; OAuth as CCOT) |
| Keycloak | https://auth.asrax.in (single prod issuer) |

## Instances

| Env | Instance IDs | Engines | Host |
|-----|--------------|---------|------|
| Dev | `pg-dev`, `mongo-dev`, `redis-dev` | POSTGRES / MONGODB / REDIS | `postgresql` / `mongodb` / `redis-master` |
| Preprod | `pg-preprod`, `mongo-preprod`, `redis-preprod` | same | same Contabo plane (tagged Preprod) |
| Prod | `pg-prod`, `mongo-prod`, `redis-prod` | same | same |

Datasources use Contabo store admins (`postgres`, Mongo `admin`, Redis `requirepass`). Free plan: instances created with `activation=false` (≤10 Community activations).

Bootstrap scripts: [`terraform/modules/apps/bytebase/scripts/`](../../../terraform/modules/apps/bytebase/scripts/).

## MCP (Marketplace → Cursor)

1. Launcher: `amctl/ai-catalog/mcp/launchers/bytebase-mcp` → `am ai sync` → `~/.asrax/bin/bytebase-mcp.cmd`
2. Enable: Marketplace / `MCP_ON_BYTEBASE=1` (default on if unset)
3. Sync IDE: `am ai mcp-sync --ide cursor --host-launchers` → reload Cursor
4. Auth: launcher logs in as **CCOT** via public `POST /v1/auth/login` (Traefik bypass) and passes Bearer to mcp-remote — **no browser OAuth**
5. Capability: **READ_ONLY** (no MCP writes)

Disable: `MCP_ON_BYTEBASE=0` then re-run mcp-sync.

## First login / verify

1. Open https://bytebase.asrax.in — **Keycloak only** (groups `am-admin` / `am-ops` / `access-bytebase-*`). SSO bridge creates/binds the Bytebase user and sets session cookies — **no Bytebase password prompt**.
2. Confirm Environments Dev / Preprod / Prod.
3. Expand `pg-*`, `mongo-*`, `redis-*` and browse synced databases/keys.
4. MCP: Cursor `bytebase` tools → list PG DBs, Mongo collections, Redis ping (see verify matrix below). CCOT password still in `~/.asrax/credentials.d/bytebase-ccot.env` for MCP / API only.

### SSO bridge (Community)

`oauth2-proxy` → `bytebase-sso-bridge` → Bytebase. Bridge reads `X-Forwarded-Email` / groups, ensures user + workspace IAM, `POST /v1/auth/login` with `web:true`, sets `access-token` / `refresh-token`. Code: `terraform/modules/apps/bytebase/sso-bridge/bridge.py`.

## Verify matrix

### Workspace

- [ ] CCOT workspaceAdmin
- [ ] Environments Dev / Preprod / Prod
- [ ] Nine instances healthy

### Instances (all)

| Env | Postgres | Mongo | Redis |
|-----|----------|-------|-------|
| Dev | `pg-dev` | `mongo-dev` | `redis-dev` |
| Preprod | `pg-preprod` | `mongo-preprod` | `redis-preprod` |
| Prod | `pg-prod` | `mongo-prod` | `redis-prod` |

### Spot-checks

- **PG:** dig `*_dev` + prod DBs; `SELECT 1` / list tables
- **Mongo:** dig `*_dev` DBs; list collections; find-limit-1 if data
- **Redis:** PING; SCAN dig prefixes e.g. `am-oms-dev:*`
- **MCP path:** `/mcp` not Keycloak 302; Marketplace + Cursor tools after OAuth

## Grown

- [x] Workspace: CCOT login + Environments Dev/Preprod/Prod + 9 instances (pg/mongo/redis × 3)
- [x] Store spot-check: PG dig DBs (`user_platform_dev`, `am_subscription_dev`) + `SELECT current_database()`; Mongo list DBs/collections path; Redis `PING` = PONG
- [x] MCP path: `/mcp` not Keycloak (403 without token); UI still Keycloak 302; `~/.asrax/bin/bytebase-mcp.cmd` + Cursor `mcp.json` has `bytebase`
- [x] Cursor MCP as CCOT — launcher Bearer via `/v1/auth/login` bypass + `tools/list` (7 tools)
- [x] SSO bridge: Keycloak-only UI (mint `access-token` → `/v1/users/me` as CCOT)
- [ ] [tests/phase-3.md](tests/phase-3.md) formal grown pack (optional follow-up)

Notes: Bytebase Free surfaces ≤10 DBs per instance after sync. Dig Mongo `*_dev` DBs were not present on Contabo at verify time (prod-named DBs synced). Redis dig key prefixes empty until apps write.
