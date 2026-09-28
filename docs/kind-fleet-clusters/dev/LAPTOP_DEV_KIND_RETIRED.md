# Laptop Kind dig — ACTIVE (local Argo)

**Status:** Dig day-to-day SoT is laptop Kind **`am-dev-apps`** + **local Argo**. Contabo dig NS soft-drained pending cleanup after dig Approve + Vault JWT proven. See [am-gitops LOCAL_KIND_DEV_ARGO_CUTOVER](https://github.com/AM-Portfolio/am-gitops/blob/main/docs/LOCAL_KIND_DEV_ARGO_CUTOVER.md) and [DEV_ON_CONTABO.md](https://github.com/AM-Portfolio/am-gitops/blob/main/docs/DEV_ON_CONTABO.md) (title kept; model is laptop dig).

## Do

- One Kind cluster: `am-dev-apps` (apps + agents workers)
- Local Argo CD in-cluster; dig AppSets `destName: am-dev-apps`
- Contabo Vault JWT + Contabo prod store FQDNs (no hostAliases, no local Vault/stores)
- Operator: `~/.asrax/kubeconfig.dev` → laptop Kind (Headlamp-ready)

## Do not

- Apply `terraform/kind-fleet/dev/{infra,platform,stores,vault-apps}` as dig SoT (no local store/Vault plane)
- Register laptop Kind API as **Contabo** Argo destination
- Point dig CSI at `vault-preprod` or Contabo dig-only DB users shared with Contabo dig NS after cleanup

## Operator

```bash
export KUBECONFIG=~/.asrax/kubeconfig.dev   # or kubeconfig.am-dev-apps.yaml
kubectl get nodes
kubectl -n am-apps-dev get pods
kubectl -n argocd get app
```

Contabo dig leftover (drain/verify only): `~/.asrax/kubeconfig.dev.contabo-bak`
