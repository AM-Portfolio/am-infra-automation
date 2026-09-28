# G20 — DR preferred writer (apps / Vault JDBC)

Steady-state preference (no dual writer):

| Store | Preferred endpoint (DR) | Contabo fallback (after promote) |
|-------|-------------------------|----------------------------------|
| Postgres | `postgres-dr.asrax.in` / WG `10.77.1.2:5432` (VPS3) | Contabo PG after `pg_ctl promote` |
| Mongo | `mongodb-dr.asrax.in` / WG `10.77.1.2:27017` | Contabo after `rs.stepUp` |

Apps and Vault mappings on the **active HTTPS site** must use the **current writer**. When CF has failed to Contabo, switch JDBC/mongo hosts in Vault (`apps/data/prod/...`) as part of the Contabo promote runbook — not via public dual DNS.

Refuse: public client use of `postgres-dr` / `mongodb-dr` beyond private/WG; dual writer.
