#!/usr/bin/env bash
set -euo pipefail
BASE=/home/am-ops/src/am-infra-automation

python3 <<'PY'
from pathlib import Path
vals = {}
for line in Path("/data/am-state/credentials/prod/oidc.env").read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    vals[k] = v.strip().strip('"').strip("'")
mapping = {
    "minio": "OIDC_MINIO_CLIENT_SECRET",
    "vault-ui": "OIDC_VAULT_UI_CLIENT_SECRET",
    "lago": "OIDC_LAGO_CLIENT_SECRET",
    "kafka-ui": "OIDC_KAFKA_UI_CLIENT_SECRET",
    "pgadmin": "OIDC_PGADMIN_CLIENT_SECRET",
    "mongo-express": "OIDC_MONGO_EXPRESS_CLIENT_SECRET",
    "redis-ui": "OIDC_REDIS_UI_CLIENT_SECRET",
    "influx-ui": "OIDC_INFLUX_UI_CLIENT_SECRET",
    "traefik": "OIDC_TRAEFIK_CLIENT_SECRET",
}
out = {k: vals.get(envk, "") for k, envk in mapping.items()}
lines = ["oidc_client_secrets = {"]
for k, v in out.items():
    if v:
        lines.append(f'  "{k}" = "{v}"')
lines.append("}")
Path("/tmp/oidc_client_secrets.auto.tfvars").write_text("\n".join(lines) + "\n")
print("keys", sorted(k for k, v in out.items() if v))
PY

cd "$BASE/terraform/kind-fleet/prod/stores"
cp /tmp/oidc_client_secrets.auto.tfvars ./oidc_client_secrets.auto.tfvars
chmod 600 ./oidc_client_secrets.auto.tfvars

terraform init -input=false >/tmp/tf-stores-init.log 2>&1 || {
  tail -50 /tmp/tf-stores-init.log
  exit 1
}

echo "=== stores plan vault+minio ==="
terraform plan -input=false -target=module.vault -target=module.minio -out=/tmp/stores-oidc.plan 2>&1 | tee /tmp/tf-stores-plan.log | tail -100
