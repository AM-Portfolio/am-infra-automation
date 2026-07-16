# 🤖 AM-INFRA: Agent Handover & Technical Context
**Last Updated: 2026-04-21**

This document serves as a critical context dump for any AI agent working on the AM-Infrastructure project. It details the "Hardening" phase and cross-platform fixes required for Windows-to-Linux VPS orchestration.

---

## 🏗️ 1. Project Architecture
- **Environment**: Hybrid (Local and VPS/Preprod).
- **Stack**: Terraform, Kubernetes (Kind), Docker, Node.js (Orchestrator).
- **Core Strategy**: "Infrastructure Lockdown" (Phase 2). Critical stateful components (PostgreSQL, MongoDB, MinIO, Vault, Authentik) are protected with `prevent_destroy = true`.

---

## 🛠️ 2. Vault & Orchestration Hardening (Current Focus)

### ✅ A. The Vault "Watcher" Pattern
- **Logic**: A Kubernetes Deployment (`watcher.tf`) runs an init-container that polls Vault's health. Once reachable, it uses an unseal key from a Secret to unlock Vault.
- **Critical Fix**: The init-container script must be **POSIX-compliant** (`/bin/sh`) and avoid `grep`. Use `curl -s -o /dev/null -w "%{http_code}"` to check for status codes 200, 429, or 503.

### ✅ B. Native Remote Tunneling (Structural Fix)
- **Problem**: `manage.js` opened Vault tunnels locally on Windows, but Terraform ran on the VPS. The remote Terraform could not reach the local Windows tunnel.
- **Solution**: The orchestrator (`terraformRunner.js`) now wraps remote Terraform commands in a native `kubectl port-forward` directly on the VPS. 
- **Precedence Rule**: In Bash, backgrounding a command (`&`) terminates the current chain. Always use `cd dir && (cmd1 &) ; cd dir && cmd2` to ensure Terraform doesn't fall back to the `/root` home directory.

### ✅ C. Idempotent Unsealing (`unsealer.tf`)
- **Logic**: A `null_resource` uses `local-exec` to run a Node.js script.
- **Constraint**: Must use `ssh -o StrictHostKeyChecking=no` for all VPS calls.
- **Idempotency**: The script checks `status.initialized` and `status.sealed`. If Vault is already unsealed, it **must** exit `0` without error to prevent Terraform from failing.

---

## 🛡️ 3. Cross-Platform Fixes (Windows → Linux VPS)

### ✅ A. Path Normalization
- **Issue**: Windows `\` vs Linux `/`.
- **Fix**: All remote paths in `manage.js` and `terraformRunner.js` are forced to forward-slashes using `.replace(/\\/g, '/')`.

### ✅ B. Secret Integrity
- **Caution**: Never pass raw JSON strings through SSH wrappers (`ssh "echo '{...}'"`) as the shell will mangle quotes and backslashes.
- **Fix**: Write JSON to a local file, `scp` it to the VPS, and create the K8s Secret from the file (`--from-file`).

---

## 📂 4. Persistence & State
- **State Root**: `/data/am-state/` (VPS).
- **Files**: `foundation.tfstate`, `vault.tfstate`, `am-preprod-config` (Kubeconfig).
- **Sync Safety**: The orchestrator syncs code exactly **once** per process (`hasSyncedThisProcess`) to prevent wiping the server's `.terraform` initialization directory during the transition from `init` to `apply`.

---

## 🚀 5. Next Steps for the Agent
1. **Identity**: Deploy `identity` (Authentik). Ensure the Vault tunnel is active (now handled automatically by the `manage.js` patch).
2. **Gateway**: Finalize `gateway` (Traefik/Cloudflare).
3. **Data Stores**: Deploy `postgresql`, `mongodb`, etc. These depend on the `vault` KV store we just initialized.

## 🔐 6. Vault Secret Seeding Status (Current State)
- **Status**: Initialized & Unsealed, but **Empty**.
- **Issue**: The first run used `n/a` placeholders because `.env` was empty.
- **Fix Pattern**: To update secrets, populate `.env` and re-run `apply -p vault`. Terraform will detect the changed variables and perform an `in-place update` of the Vault KV secrets.

## 🔄 7. Re-run Safety (Idempotency)
- **Vault Apply**: 100% safe to re-run. The `unsealer` logic now checks `status.initialized` and `status.sealed` natively on the VPS. If already unsealed, it exits `0`.
- **Duplicate Prevention**: The orchestrator (`manage.js`) maintains state on the VPS. Re-running will **not** create duplicate pods or helm releases; it will only synchronize the configuration.

---
*Reference updated by Antigravity (Advanced Agentic Coding Team)*
