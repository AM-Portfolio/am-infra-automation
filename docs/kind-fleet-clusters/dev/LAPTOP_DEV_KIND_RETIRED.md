# Laptop Kind dig — RETIRED for Contabo dig track

**Status:** Retired for day-to-day dig. Dig workloads run on Contabo (`am-vps-nonprod` / `am-apps-dev`) with Contabo Argo. See [am-gitops DEV_ON_CONTABO](https://github.com/AM-Portfolio/am-gitops/blob/main/docs/DEV_ON_CONTABO.md).

## Do not

- Apply `terraform/kind-fleet/dev/{infra,platform,stores,vault-apps}` for dig SoT
- Run local dig Argo / local Vault / local Keycloak for Contabo dig apps
- Register laptop Kind API as Contabo Argo destination
- Use laptop dig kubeconfig for Contabo dig ops (use `~/.asrax/kubeconfig.dev`)

## Optional keep (local experiments only)

Laptop Kind may still exist for offline experiments. It is **not** the Contabo dig pilot path and must not share Contabo dig DB users or dig Vault roles used by Contabo dig NS.

## Contabo dig operator

```bash
# From am-gitops
./scripts/kubeconfig-dev-from-nonprod.sh
export KUBECONFIG=~/.asrax/kubeconfig.dev
kubectl -n am-apps-dev get pods
```
