# 🛡️ Infrastructure Disaster Recovery (DR) & State Management

This document directly addresses the critical architecture of how your passwords are generated, where they are stored, and what happens in catastrophic failure scenarios (like accidental cluster or VPS deletion).

## 1. Password Origination: "The Bootstrap Seed"

When your infrastructure is first provisioned, it relies on the `bootstrap` module located at `terraform/modules/core/bootstrap/main.tf`.

- **How it works**: Terraform uses the `random_password` resource to dynamically generate complex cryptographic strings for Vault, Authentik, PostgreSQL, MongoDB, Redis, and InfluxDB.
- **Where it is stored**: These passwords physically live in **Plain Text** inside the specific Terraform State file (`terraform.tfstate`) that executed the module. From there, scripts pull these values and write them into `infrastructure-secrets/latest/credentials.txt` and `.env`.

## 2. Disaster Scenarios & Recovery Paths

You expressed concern: *"What if the cluster is deleted by mistake, where will I retrieve it?"*

Here are the exact scenarios based on your current architecture:

### 🟢 Scenario A: Kubernetes Cluster is Accidental Deleted
- **The Event**: Someone runs `kind delete cluster` locally, or deletes the nodes on the VPS.
- **The Impact**: All running pods (Vault, DBs) and internal Kubernetes Secrets are wiped out.
- **The Recovery**: **Safe.** As long as your `terraform.tfstate` files still exist on your disk, Terraform remembers the exact `random_password` strings it generated. When you re-run the orchestrator (`manage.js`), Terraform will simply recreate the Kubernetes cluster, recreate the secrets using the *exact same passwords*, and reconnect to your persistent storage volumes seamlessly.

### 🔴 Scenario B: Local Server / Disk Wipe
- **The Event**: Your local `c:\Users\user\OneDrive\Documents\am-repos\...` folder is completely deleted.
- **The Impact**: Catastrophic. You lose the `.tfstate` files. The `random_password` memory is gone forever. Even if the cluster is still running, you cannot authenticate to Vault or the databases because you no longer know the passwords, and Terraform cannot manage the existing infrastructure.
- **The Recovery**: Because your repository is located in a `OneDrive` synced folder, your state files are intrinsically backed up by Microsoft. You would restore the folder from OneDrive history to recover your passwords.

### 🔴 Scenario C: VPS Deletion (The "Sunday Access" Problem)
- **The Event**: Your Cloud Provider terminates your VPS abruptly, or the `/root/am-infra` directory is wiped. (This is the scenario you specifically worried about).
- **The Impact**: Catastrophic. When `manage.js apply -e preprod` runs, it executes Terraform directly on the VPS disk. If the VPS disk is wiped, the `preprod` state files (and therefore your production database passwords) are permanently erased.
- **The Recovery**: **Currently, None.** The data would be lost.

---

## 3. Enterprise Best Practice: Remote State (How to Fix Scenario C)

Right now, your Terraform State is structurally bound to the local disk it runs on. In a true enterprise environment, state files are *never* left on a lonely VPS drive.

If you are serious about Disaster Recovery, the immediate next architectural step is to implement **Terraform Remote Backend**.

### The Action Plan:
1. **Create an S3 Bucket** (AWS) or **Azure Blob Container**.
2. **Enable Versioning** on the bucket so every password rotation is permanently archived.
3. **Change the Provider configuration**: Rather than storing state locally, we update `terraform { backend "s3" { ... } }`.

**The Result**: If your VPS is completely nuked from orbit, it doesn't matter. You spin up a new $5 VPS, install Terraform, and the exact moment you run `terraform init`, it downloads the state from S3, remembers every password, and recreates the infrastructure perfectly.

*(Note: Until a Remote Backend is configured, you must manually ensure that the `/root/am-infra/terraform/*/*.tfstate` files on your VPS are being backed up via a cron job or external script).*
