# Dig/dev IAM pilot (access plane)

Pilot track for AM access plane: **create + test dig (`env=dev`) before Contabo prod promote**.

Loop (same as [prod/README.md](../prod/README.md)):

```text
Prereq → Implement → Test → Grown → next
```

**Gate:** Contabo promote (`prod/iam/`) only after [phase-5-grown.md](phase-5-grown.md) sign-off.

**Pilot host (locked):** Laptop Kind dig is [RETIRED](../LAPTOP_DEV_KIND_RETIRED.md). Dig workloads = Contabo `am-apps-dev`; dig store principals = Contabo infra Kind (`kubeconfig.prod`) with `*_dev` users from `catalog/dig-contabo-users.yaml`. Optional laptop `kind-fleet/dev/stores` remains catalog SoT for offline experiments only.

## Phase map

| Phase | Doc | Tests |
|-------|-----|-------|
| IAM-0 | [README](README.md) (this) | baseline below |
| IAM-1 | [phase-1-keycloak.md](phase-1-keycloak.md) | [tests/phase-1.md](tests/phase-1.md) |
| IAM-2 | [phase-2-db-users.md](phase-2-db-users.md) | [tests/phase-2.md](tests/phase-2.md) |
| IAM-3 | [phase-3-bytebase.md](phase-3-bytebase.md) | [tests/phase-3.md](tests/phase-3.md) |
| IAM-4 | [phase-4-dig.md](phase-4-dig.md) | [tests/phase-4.md](tests/phase-4.md) |
| IAM-5 | [phase-5-grown.md](phase-5-grown.md) | matrix in file |
| IAM-6 | Contabo: `../prod/iam/` | after dig Grown |
| IAM-V | later Vault CSI | not pilot |

## Layers

| Layer | SoT | Dig / Contabo dig host |
|-------|-----|------------------------|
| Humans/teams | Keycloak realm roles → token `groups` | **One** Contabo Keycloak: `auth.asrax.in` / `am-realm` (DR Keycloak = backup only; no dig issuer) |
| Service principals | `db-users` catalog + Jobs | Contabo infra stores + `dig-contabo-users.yaml` |
| Explore | Bytebase + existing kafka-ui | Contabo dig URLs |
| Counts | ConfigMap `infra/db-users-inventory` | Contabo infra `infra` NS |

## IAM-0 inventory (baseline)

### Dig store plane

| Item | Value |
|------|--------|
| Contabo dig apps | `~/.asrax/kubeconfig.dev` → `am-apps-dev` |
| Contabo stores (shared plane) | `~/.asrax/kubeconfig.prod` → `infra` (PG/Mongo/Redis/Kafka/MinIO) |
| Catalog (prod names) | `terraform/modules/core/db-users/catalog/users.yaml` |
| Catalog (dig Contabo `*_dev`) | `…/catalog/dig-contabo-users.yaml` |
| Provision script | `…/db-users/scripts/provision-dig-contabo-users.ps1` |
| Optional laptop dig TF | `terraform/kind-fleet/dev/stores` (not Contabo dig SoT) |
| Contabo dig Vault seed | `dev/vault-apps-contabo` — `dig_vault_seed` + `DIG_PRINCIPAL_SEED` (IAM-4; no prod admin copy) |

### Shared admin snapshot (post IAM-4 + store isolation)

- Dig Vault `apps/data/dev/infra/{mongodb,postgres,redis,kafka,influxdb}` uses **`dig_vault_seed`** (Influx: dig-only token) from `DIG_PRINCIPAL_SEED` / dig stores env — not Contabo prod admin.
- Store **hosts** remain Contabo FQDNs (`store_hosts=contabo_prod`). Apps use **per-service `*_dev` resource names** (DBs / Redis prefixes / Kafka topic prefixes / Influx `am_dev`).
- Bidirectional: Contabo `am_prod` (Mongo/Redis) and unprivileged PG roles cannot use `*_dev`; dig cannot use prod resources.
- Provision: `provision-dig-contabo-users.ps1` + catalog `dig-contabo-users.yaml`.

### Implement (IAM-0)

- [x] Create `docs/kind-fleet-clusters/dev/iam/` stubs
- [x] Inventory dig Contabo vs Contabo prod store share
- [x] Confirm Contabo infra Ready (`kubeconfig.prod`); laptop dig Kind not required

### Test (IAM-0)

- [x] Contabo Keycloak OIDC discovery 200 (`auth.asrax.in/realms/am-realm`)
- [x] kafka-ui / Grafana / MinIO reachable (baseline 200; kafka-ui pod may ImagePullBackOff in-cluster)

### Grown

- [x] Doc stubs + inventory ready → IAM-1
