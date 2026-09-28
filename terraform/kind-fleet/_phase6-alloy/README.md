# Phase 6 Alloy one-shot helper

Applies `modules/core/alloy-logs` against an existing kubeconfig (does not recreate Kind).

Fleet SoT remains:

- `terraform/kind-fleet/prod/{apps,infra}/alloy.tf`
- `terraform/kind-fleet/dr/{apps,infra}/alloy.tf`
- `terraform/kind-fleet/preprod/apps/alloy.tf`

Day-2 prefer those roots on VPS / Contabo, or `scripts/kind-fleet/install-alloy.py`.

```bash
terraform -chdir=terraform/kind-fleet/_phase6-alloy init
terraform -chdir=terraform/kind-fleet/_phase6-alloy apply \
  -var='kubeconfig=~/.asrax/kubeconfig.am-prod-apps.yaml' \
  -var='kube_context=kind-am-prod-apps' \
  -var='cluster_name=am-prod-apps' \
  -var='environment=prod'
```
