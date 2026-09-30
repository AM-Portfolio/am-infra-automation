# IAM-4-DEV — Dig off Contabo prod admin + store isolation

## Prereq

Prefer dig Kind local stores + IAM-2 users. Dig apps must not need Contabo `mongo.asrax.in` **admin**. Dig shares Contabo store **hosts** (`postgres|mongo|redis.asrax.in`) but uses `dig_vault_seed` + per-service `*_dev` resource names from `DIG_PRINCIPAL_SEED`. Isolation is **bidirectional**: dig cannot touch prod resources; prod app principal `am_prod` cannot touch `*_dev`.

## Implement

- [x] Stop `vault-apps-contabo` reading Contabo `apps/data/prod/infra/*` passwords
- [x] Dig Vault seed uses `dig_vault_seed` + DIG_PRINCIPAL_SEED (`postgres_user`/`mongo_user` = `dig_vault_seed`; hosts stay `store_hosts=contabo_prod` FQDNs — dig has no separate store plane)
- [x] Shared env=dev login per engine; Vault overlays inject per-service `*_dev` DB/prefix/topic/bucket names
- [x] Mongo: `dig_vault_seed` RW only on catalog `*_dev` DBs; `am_prod` RW only on prod DB names
- [x] Postgres: `dig_vault_seed` owns `user_platform_dev` / `am_subscription_dev`; `REVOKE … FROM PUBLIC`
- [x] Redis: ACL `dig_vault_seed` → `am-*-dev:` only; `am_prod` → prod prefixes only
- [x] Kafka: Vault topic prefixes `am.*.dev.*` (SCRAM/ACL deferred while Contabo PLAINTEXT)
- [x] Influx: bucket `am_dev` + dig-only token; prod token scoped to bucket `am`
- [x] Re-apply dig vault-apps (`terraform -chdir=kind-fleet/dev/vault-apps-contabo apply`) without prod copy

## Grown

- [x] [tests/phase-4.md](tests/phase-4.md) green (incl. bidirectional store isolation)
