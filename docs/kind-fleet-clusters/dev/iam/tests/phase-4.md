# IAM-4 tests (dig)

- [x] Dig Vault mongodb/postgres/redis password ≠ Contabo prod admin; users = `dig_vault_seed`
- [x] Dig apps namespaces present on Contabo dig (`kubeconfig.dev`); vault-apps-contabo applied (`iam4_note` output)
- [x] Vault env=dev mongo username shared (`dig_vault_seed`); password ≠ prod; portfolio DB = `am_portfolio_dev`
- [x] Mongo bidirectional: dig writes `am_portfolio_dev` OK; dig write prod `portfolio` DENIED; `am_prod` write `am_portfolio_dev` DENIED; `am_prod` write `portfolio` OK
- [x] Postgres bidirectional: dig writes `user_platform_dev` OK; non-granted role CONNECT to `*_dev` DENIED
- [x] Redis bidirectional: dig SET `am-*-dev:` OK / prod prefix NOPERM; `am_prod` SET prod OK / `*-dev:` NOPERM
- [x] Kafka: Vault `KAFKA_TOPIC_PREFIX=am.market.dev.` (ACL deferred until Contabo SASL)
- [x] Influx bidirectional: dig token write `am_dev` 204 / `am` 403; prod token write `am` 204 / `am_dev` 403
- [x] Sample dig deploys restarted (many scaled to 0 on Contabo dig — Vault CSI picks up `*_dev` names on next scale-up)
