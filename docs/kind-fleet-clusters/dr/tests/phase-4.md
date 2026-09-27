# DR Phase 4 / 5 gates (Vault + Argo waves)

Same contract as prod — **no disposable `dr-phase*.sh` / `tmp-*` probes**. Extend `phase_gates` or fix via am-gitops / TF PR.

```bash
cd /path/to/am-infra-automation
PYTHONPATH=scripts/kind-fleet python -m phase_gates --env dr --wave 4a
PYTHONPATH=scripts/kind-fleet python -m phase_gates --env dr --wave 4d
PYTHONPATH=scripts/kind-fleet python -m phase_gates --env dr --wave 4e
PYTHONPATH=scripts/kind-fleet python -m phase_gates --env dr --wave 4f
```

| Wave | Gate | Assert |
|------|------|--------|
| 4a | `4a_vault_csi` | Vault `apps/data/dr/infra/postgres` readable via CSI login |
| 4d | `4d_identity` | token → `/identity/admin/roles` 200; iss `auth-dr` |
| 4e | `4e_market` | `/market/actuator/health` 200; quotes RELIANCE 200 |
| 4f | `4f_apps` | portfolio/trade/doc/news/analysis health + authenticated portfolio |

Sync: `argocd app sync <service>-dr` on platform cluster (Manual). Desired state → am-gitops overlay PR only.

Do **not** sync product Argo apps in Phase 4 Vault — that is [phase-5-argo.md](../phase-5-argo.md).
