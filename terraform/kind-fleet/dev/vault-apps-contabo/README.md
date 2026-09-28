# Contabo Vault apps seed (env=dev)

See [contabo-vault-one](../../../../docs/kind-fleet-clusters/contabo-vault-one/TF-OUTLINE.md).

```text
.\init-backend.ps1 -Env dev -Role vault-apps-contabo
terraform -chdir=dev/vault-apps-contabo init -backend-config=backend.hcl
terraform -chdir=dev/vault-apps-contabo plan
terraform -chdir=dev/vault-apps-contabo apply
```

Do **not** apply while `https://vault.asrax.in` returns CF 530.
