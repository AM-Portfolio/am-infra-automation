# 🌌 AM-Enterprise: High-Availability Infrastructure Hub

Welcome to the **10/10 Enterprise Orchestration Center**. This repository is the source of truth for a modular, zero-trust infrastructure stack managed by the **`am`** CLI.

---

## 🚀 The AM Universal CLI (`am`)

To ensure you can use the clean `am` command without colliding with existing Windows system tools, simply run this one-time command in your PowerShell terminal to bind it:

```powershell
function am { & "$PWD\am.cmd" @args }
```
*(Tip: Add this line to your PowerShell `$PROFILE` to make it permanent!)*

Now you can use `am` as your master entry-point: `am [action]` for Local, and `am vps:[action]` for the remote VPS.

---

## 🎯 Command Mastery: Operations by Category

We manage the infrastructure in three distinct layers of granularity:
1. **Module Level**: A single specific app (e.g., `vault`, `postgresql`).
2. **Group Level**: A logical stack of apps (e.g., `dbs`, `core`, `monitoring`).
3. **Global Level**: The entire total environment.

Here is your complete guide to executing updates, backups, and deletions across these layers.

### 🟢 1. Build & Update Operations
Terraform is "Idempotent." To update an app, you simply run the build command again. It scans your code and only applies the differences.

| Granularity | Example Command | Description |
| :--- | :--- | :--- |
| **Module (Local)** | `am apply -a vault` | Builds or updates *only* Vault on your local machine. |
| **Group (Local)** | `am apply -a dbs` | Builds/updates all databases (Postgres, Mongo, Redis). |
| **Global (Local)** | `am apply` | Deploys the entire local target architecture. |
| **Module (VPS)** | `am vps:apply -a identity` | Syncs code and updates Authentik on the remote VPS. |
| **Global (VPS)** | `am vps:apply` | Syncs code and builds the full VPS environment. |

### 💾 2. Backup & State Management
Terraform stores the memory of your infrastructure in a State file (`terraform.tfstate`). This is your backup and brain.

| Granularity | Example Command | Description |
| :--- | :--- | :--- |
| **Module** | `am plan -a vault` | "Dry Run" review. Checks Vault's state and prepares a backup. |
| **Group** | `am plan -a core` | Reviews and backs up the state for the Core foundation. |
| **Global** | `am plan` | Complete review of the environment against the live servers. |

> [!TIP]
> **Automatic Backups:** Every time you run `am apply`, Terraform automatically creates a `terraform.tfstate.backup` file before making any changes.

### 🔴 3. Delete & Cleanup Operations
All destructive operations are protected by the "Mana-Mod" multi-step confirmation lock. Physical data (`/mnt/am-infra/data/`) is **immortal** and is not deleted by standard destroy commands.

| Granularity | Example Command | Description |
| :--- | :--- | :--- |
| **Module** | `am destroy -a kafka` | Gracefully removes Kafka. Requires `YES` & `CONFIRM`. |
| **Group** | `am destroy -a monitoring`| Removes Grafana & Headlamp. Leaves other apps running. |
| **Global** | `am destroy` | Destroys the whole environment cleanly via Terraform. |
| **Factory Wipe** | `am factory-reset` | The "Nuke" option. Deep-cleans Docker networks, containers, and state files. Offers an override to explicitly `PURGE DATA`. |

---

## 🏗️ Technical Pillar: Data Immortality
Even if you run a **Factory Reset** and delete your "Execution Layers," your physical data (Databases, Vault storage) stays safe.
- **Host Storage:** Mapped to `/mnt/am-infra/data/`.
- **Safeguard:** This data is **NEVER** deleted by standard commands unless you explicitly use the `PURGE DATA` override in the factory reset.