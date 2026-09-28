# Which apps need your IP enabled

Operator cheat sheet for Cloudflare Access + data-plane TCP.  
Register CIDRs via [`.github/workflows/register-access-ip.yml`](../.github/workflows/register-access-ip.yml) (`apps` = comma-separated keys below).  
Registry: [`terraform/kind-fleet/access-allowlist/registry.json`](../terraform/kind-fleet/access-allowlist/registry.json).  
Parent: [ZERO_TRUST_ACCESS.md](ZERO_TRUST_ACCESS.md).

**Enforce note:** IP policies matter when `access_enforce=true` (ZT-P1). Until then, register anyway so apply is ready.

## Quick pick (ops laptop / home)

Use this `apps` value for day-to-day ops:

```text
store-uis,data-plane,obs,platform-ops,platform-tools
```

Optional product UI:

```text
store-uis,data-plane,obs,platform-ops,platform-tools,product-ui
```

Never register `auth` (IdP is not behind Access).

## App keys → hosts / ports

| App key | IP needed? | What you get access to | Roles |
|---------|------------|------------------------|-------|
| **`store-uis`** | **Required** | `pgadmin`, `mongo-express`, `redis-ui`, `kafka-ui`, `minio`, `influx` (env suffix: bare prod, `-dev` / `-preprod` / `-dr` when used) | ops, admin, super_admin |
| **`data-plane`** | **Required** | TCP only — Postgres, Mongo, Redis, Kafka, MinIO API, Influx, Vault, Temporal gRPC (exposer / host firewall) | ops/admin CIDRs |
| **`obs`** | Yes (ops) | `grafana.asrax.in`, `loki.asrax.in`, `prometheus.asrax.in` | ops, admin, super_admin |
| **`platform-ops`** | Yes (ops) | `argocd`, `vault` UI, `temporal`, `traefik` (+ env suffix) | ops, admin, super_admin |
| **`platform-tools`** | Yes (ops) | `n8n`, `openproject`, `lago`, `growthbook`, `litellm`, `langfuse`, `novu` (+ env suffix) | ops, admin, super_admin |
| **`product-ui`** | Optional | Product UI host (e.g. `am-dev.asrax.in` / `am.asrax.in`) | user, viewer, ops, admin, super_admin |
| **`auth`** | **N/A** | Keycloak / `auth*.asrax.in` — **no Access app** | — |

Env host pattern: `{name}.asrax.in` (prod) or `{name}-{env}.asrax.in` for non-prod where the TF module uses a suffix.

## Built-in CIDRs (no registration)

| CIDR | Why |
|------|-----|
| `172.19.0.0/16` | Kind docker network |
| `10.77.1.0/24` | WireGuard mesh |

## How to enable your IP

1. Actions → **Register access IP** (Environment `zero-trust-ip`).
2. `action=add`, `cidr=<your-public-ip>/32`, `apps=` (see Quick pick), `reason=…`.
3. Merge the PR that updates `registry.json`.
4. `terraform apply` on the edge / data-plane roots that consume the registry (see ZERO_TRUST_ACCESS.md).

End users / `user` role do **not** self-serve IP adds.
