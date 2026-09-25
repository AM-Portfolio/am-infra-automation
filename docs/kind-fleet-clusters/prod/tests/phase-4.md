# Phase 4 gates (Kind-fleet apps waves)

Runner (VPS or laptop with kube/vault access):

```bash
cd /path/to/am-infra-automation
PYTHONPATH=scripts/kind-fleet python -m phase_gates --env prod --wave 4a
PYTHONPATH=scripts/kind-fleet python -m phase_gates --env prod --wave 4d
```

| Wave | Gate | Assert |
|------|------|--------|
| 4a | `4a_vault_csi` | Vault `apps/data/<env>/infra/postgres` readable |
| 4b | `4b_argo` | ArgoCD namespace / roots reachable |
| 4c | `4c_edge` | `am.<domain>/` 200; `/gateway` 401/403 |
| 4e | `4e_market` | `/market/actuator/health` 200; `/market/v1/market-data/quotes?symbols=RELIANCE` 200 |
| 4f | `4f_apps` | portfolio/trade/doc/news/analysis health; `/portfolio/v1/portfolios` 200 with token |

Sync helper (VPS): `scripts/kind-fleet/wave_4f_sync.py` — apply Application CRs from local gitops + Argo sync (`--start-from` to skip Ready apps). Kind-fleet hostAliases pin stores to exposer `172.18.0.6`; portfolio ships with `PORTFOLIO_REDIS_ENABLED=false` until Lettuce hang is fixed.

Sync Keycloak admin into Vault before vault-apps re-apply / identity roll:

```bash
PYTHONPATH=scripts/kind-fleet python3 scripts/kind-fleet/sync_keycloak_admin_to_vault.py --env prod
```

Static TF contracts (no cluster):

```bash
terraform -chdir=terraform/modules/core/apps-vault-seed init -backend=false
terraform -chdir=terraform/modules/core/apps-vault-seed test
```

Do **not** add disposable `tmp-p4*.sh` probes — extend `scripts/kind-fleet/phase_gates`.

Traefik strip/cors for prod apps: `terraform -chdir=terraform/kind-fleet/prod/apps apply` (`middlewares.tf`). Do not kubectl-patch Middleware CRs.
