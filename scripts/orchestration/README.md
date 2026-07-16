# 🚀 AM-Infrastructure Orchestrator (v2.0)

Welcome to the **Enterprise Orchestration System**. This folder contains `manage.js`—a clean, modular, and highly intelligent wrapper for deploying your Terraform layered architecture safely across environments.

## 🆕 What's New & Fixed (v2.0 Refactor)

We have implemented several critical enterprise structural fixes to stabilize the deployment pipeline:
- **Modularized Scripts**: Moved logic from a monolithic `manage.js` into reusable libraries in `scripts/shared/lib/` (`envManager.js`, `dependencyGraph.js`, `terraformRunner.js`).
- **Strict Provider Scoping**: Stripped redundant and unauthenticated provider blocks from internal modules. Layers now only initialize the providers they *exactly* need, preventing "Chicken-and-Egg" deadlocks (e.g., Data-stores no longer tries to connect to Authentik/Cloudflare before they exist).
- **Centralized Kubeconfig**: Eliminated the dangerous duplication of `kubeconfig.yaml` files. All layers now natively reference `~/.kube/config`.
- **Intelligent Auto-Fulfillment**: The orchestrator now understands the infrastructure dependency tree and auto-builds prerequisites.

---

## 📚 1. Layering Architecture & Build Order

The infrastructure is designed in logical layers to reduce the "blast radius" of changes and improve performance. The **Order of Operations** is strictly enforced by the orchestrator:

1.  **`foundation`**: The bedrock. Builds the Kind cluster and core namespaces.
    - *Dependencies*: None.
2.  **`vault`** ⭐ **NEW LAYER — The source of truth.** Deploys HashiCorp Vault, auto-unseals it, mounts the KV-V2 engine (`secret/`), and seeds *all* infrastructure credentials from your `.env` into structured paths (`secret/infra/gateway`, `secret/infra/databases`, etc.). Every subsequent layer reads from Vault — not from variables.
    - *Dependencies*: `foundation`.
3.  **`gateway`**: Provisions Traefik and Cloudflare Tunnel. Reads its API tokens from `vault_kv_secret_v2`.
    - *Dependencies*: `foundation`, `vault`.
4.  **`identity`**: Provisions Authentik and registers the SSO Outpost *before* any databases exist. Reads its bootstrap token from Vault.
    - *Dependencies*: `foundation`, `vault`, `gateway`.
5.  **`data-stores`**: Provisions PostgreSQL, MongoDB, Redis, and InfluxDB. Reads DB root passwords from Vault. Web UIs (pgAdmin, Mongo-Express) are automatically protected behind the Authentik SSO middleware via Traefik.
    - *Dependencies*: `foundation`, `vault`, `gateway`, `identity`.
6.  **`monitoring`**: Provisions Grafana and Prometheus. Reads Grafana admin password from Vault. Protected by Authentik SSO.
    - *Dependencies*: All above.
7.  **`platform` / `runner`**: GitHub Runner and additional application services. Reads GitHub PAT from Vault.
    - *Dependencies*: `monitoring`, `identity`.

---

## 🛠️ 2. The Auto-Fulfillment Engine

The system features an **Intelligent Dependency Graph** (located in `shared/lib/dependencyGraph.js`). 

**How it works:**
If a developer runs:
```bash
node scripts/orchestration/manage.js apply -p identity
```
The orchestrator will intelligently intercept this command:
1. It checks the graph and sees `identity` requires `data-stores`.
2. It natively inspects the local Terraform state. 
3. If `data-stores` is not yet applied, the orchestrator will **pause**, build `data-stores` first, and then resume `identity`.

---

## 🏗️ 3. Verification & Visualization

After each deployment, you should verify the health of the layer.

### A. Connectivity Diagnostics
Use the smart orchestrator diagnostics to check if services are responding:
```bash
python scripts/diagnostics/check_connectivity.py --layer=data-stores
```

### B. Infrastructure Visualization (The "Viz" Layer)
We have added state visualization support. The orchestrator generates visualization snapshots that can be used to audit the complexity and health of your graph:
- **State Map**: `terraform/viz-state.json`
- **Plan Audit**: `terraform/viz-plan-utf8.json`
*Note: Use these files with your visualization dashboard to see the real-time resource hierarchy.*

---

## 🏗️ 4. Terraform Best Practices (The Golden Rules)

To ensure this Orchestrator works flawlessly, stay aligned with these rules:
- **config_path**: Always use `~/.kube/config` (never repeat `./kubeconfig.yaml`).
- **Strict Scoping**: Root modules inside `identity/local` or `data-stores/local` should only declare minimum providers.
- **Inheritance**: Sub-modules (in `modules/`) should **never** have `provider` blocks; they must inherit them from the root.

---

## 💻 5. Command Line Usage

| Command | Description |
| :--- | :--- |
| `node manage.js init -p <pkg>` | Initialize a specific package layer |
| `node manage.js plan -p <pkg>` | Plan changes for a layer |
| `node manage.js apply -p <pkg>` | Apply a layer (With auto-dependency fulfillment) |
| `node manage.js destroy -p <pkg>` | Teardown a specific layer safely |

**Example**: `node scripts/orchestration/manage.js apply -p identity -e local`

---

## 🔒 6. Smart Secret Resolution & Credential Flow

The system implements a **3-tier credential resolution** strategy so the infrastructure deploys successfully even without a pre-populated `.env` file.

### How it works

```
.env file present?
    ├── YES → manage.js reads it, injects TF_VAR_* into Terraform
    │          Terraform uses those exact values → seeds into Vault
    └── NO  → Terraform generates random_password for each secret
               → automatically seeds them into Vault
               → All downstream layers read from Vault (same behaviour either way)
```

### Vault KV Secret Paths

All paths are **environment-scoped** — `local` and `preprod` secrets never overwrite each other even if both point at the same Vault instance.

| Path | Contents |
|:-----|:---------|
| `secret/<env>/infra/gateway` | `cloudflare_token`, `cloudflare_account_id`, `cloudflare_zone_id`, `cloudflare_tunnel_secret` |
| `secret/<env>/infra/databases` | `postgresql_password`, `mongodb_password`, `redis_password`, `influxdb_token`, `grafana_password` |
| `secret/<env>/infra/identity` | `authentik_bootstrap_token`, `authentik_secret_key` |
| `secret/<env>/infra/platform` | `github_pat` |
| `secret/<env>/infra/db-users/*` | Per-app database credentials (written by `db-users` module) |

**Examples:**
- Local: `secret/local/infra/databases`
- Preprod: `secret/preprod/infra/databases`

### How downstream layers read from Vault

Every layer after `vault` uses a Terraform `data` source — **never a raw variable**:

```hcl
data "vault_kv_secret_v2" "databases" {
  mount = "secret"
  name  = "infra/databases"
}

# Then use in resources:
resource "helm_release" "postgresql" {
  set {
    name  = "auth.password"
    value = data.vault_kv_secret_v2.databases.data["postgresql_password"]
  }
}
```

> [!NOTE]
> The only exception is `vault_root_token` — this is needed to authenticate the Vault provider itself and is injected by manage.js from `credentials.txt`.

