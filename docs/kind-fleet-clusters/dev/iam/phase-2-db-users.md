# IAM-2-DEV — db-users catalog + inventory (dig)

## Prereq

IAM-1 Grown. Dig Kind infra Ready; stores accept Jobs.

## Implement

- [ ] Catalog: `terraform/modules/core/db-users/catalog/users.yaml`
- [ ] Module: kafka SCRAM/ACL jobs + inventory ConfigMap; Redis prefix ACL
- [ ] Wire dig `kind-fleet/dev/stores` to full catalog (`enable_vault_secrets=false`)
- [ ] TF apply dig stores; Jobs complete
- [ ] ConfigMap `infra/db-users-inventory` present

## Grown

- [ ] [tests/phase-2.md](tests/phase-2.md) every-user table green
