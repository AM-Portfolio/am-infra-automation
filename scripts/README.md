# 🌌 AM-Infrastructure Scripts & Automation

This directory contains the core automation engine for the **AM-Platform**. These scripts handle everything from Kubernetes orchestration and secret synchronization to network bridging and health diagnostics.

---

## 🚀 The Hybrid Orchestrator (`orchestration/manage.js`)

The `manage.js` script is the primary entry point for all infrastructure operations. It provides a high-level wrapper around Terraform, allowing you to target specific "Packages" or "Apps" without managing complex state paths manually.

### Common Commands
```powershell
# Initialize all providers
node scripts/orchestration/manage.js init

# Deploy the Monitoring stack (Grafana, Prometheus, etc.)
node scripts/orchestration/manage.js apply -p monitoring

# Plan changes for a specific database
node scripts/orchestration/manage.js plan -a mongodb

# Destroy a specific module (e.g., identity)
node scripts/orchestration/manage.js destroy -a identity
```

---

## 📂 Category Reference

### 🛠️ Orchestration (`/orchestration`)
| Script | Language | Description |
| :--- | :--- | :--- |
| `manage.js` | JS | **Primary Hub**. Automated Terraform wrapper with app-wise targeting. |
| `factory_reset.js` | JS | The "Nuke" button. Wipes Kind cluster and local data volumes for a fresh start. |
| `infra.py` | Python | Logic for managing the 6-tier infrastructure lifecycle. |
| `infra-up.ps1` | PWSH | One-click script to stand up the cluster and base networking. |

### 🔐 Security & Secrets (`/security`)
| Script | Language | Description |
| :--- | :--- | :--- |
| `manage_secrets.py` | Python | **Master Secret Sync**. Pulls Terraform outputs into `.env` and `credentials.txt`. |
| `vault_unseal.py` | Python | Automated Vault unsealer. Safely retrieves unseal keys from K8s secrets. |
| `sync-secrets.py` | Python | Synchronizes local secrets with the remote Vault instance across tiers. |
| `restore-oidc.ps1` | PWSH | Specialized recovery for Authentik/OIDC provider configurations. |

### 🌐 Networking (`/networking`)
| Script | Language | Description |
| :--- | :--- | :--- |
| `port-forward.ps1` | PWSH | One-click relay. Forwards all internal ports (5432, 27017, 8200, etc.) to localhost. |
| `ssh_bridge.py` | Python | Establishes persistent SSH tunnels to the remote VPS. |
| `sync_vscode_ports.py` | Python | Logic to auto-open ports in VSCode remote sessions. |

### 🩺 Diagnostics (`/diagnostics`)
| Script | Language | Description |
| :--- | :--- | :--- |
| `check_connectivity.py` | Python | **Health Suite**. Tests connectivity and auth for 7+ services (Mongo, PG, Kafka, Vault, etc.). |
| `test_all_connections.py` | Python | Bulk verification tool for verifying entire stack reachability. |

---

## 📚 Shared Library (`/shared/lib`)

The Python scripts leverage a shared library to ensure consistent behavior across environments:

- **`env.py`**: Smart loading of `.env` and `infrastructure-secrets`.
- **`logger.py`**: Beautiful, color-coded console output with timestamps.
- **`ui.py`**: Interactive terminal elements (spinners, progress bars).
- **`vps.py`**: Abstraction layer for remote command execution on the VPS.

---

> [!TIP]
> **Pro Tip**: Always run `node scripts/orchestration/manage.js plan` before an apply to see exactly what modules are being targeted by the Hybrid Orchestrator.

> [!IMPORTANT]
> **Environment Context**: Most scripts respect the `AM_ENV` environment variable (`local`, `vps-tunnel`, `vps-direct`). Default is usually `local`.
