# 🚀 Team Infrastructure Access Guide - AM Portfolio

This guide contains the finalized connection details and credentials for the production-grade infrastructure on the VPS (`203.174.22.129`).

---

## 🔐 1. HashiCorp Vault (Secrets Management)

Vault is the "Single Source of Truth" for all production secrets.

- **Web UI**: [http://vault.munish.org](http://vault.munish.org)
- **Root Token**: `<PLACEHOLDER_VAULT_ROOT_TOKEN>`
- **Unseal Key**: `<PLACEHOLDER_VAULT_UNSEAL_KEY>`
- **Policy Pattern**: Secrets are stored under `kv/data/preprod/...`.

> [!IMPORTANT]
> **App Authentication**: Developers should NOT use the Root Token in code. Applications are configured to use **Kubernetes Auth** automatically via their Service Accounts.

---

## 🎨 2. Headlamp (Kubernetes Dashboard)

The primary UI for monitoring pods, logs, and cluster health.

- **URL**: [http://headlamp.munish.org](http://headlamp.munish.org)
- **Login Method**: Select **"Token"**
- **Permanent Access Token**:
  ```text
  <PLACEHOLDER_HEADLAMP_ACCESS_TOKEN>
  ```

---

## 🗄️ 3. Database Cluster

All databases use the password `@A1srax` for the default admin users.

| Resource       | Hostname (Internal K8s)              | Port  | Default User       |
| :------------- | :----------------------------------- | :---- | :----------------- |
| **PostgreSQL** | `postgresql.infra.svc.cluster.local` | 5432  | `postgres`         |
| **MongoDB**    | `mongodb.infra.svc.cluster.local`    | 27017 | `admin`            |
| **Redis**      | `redis.infra.svc.cluster.local`      | 6379  | No User (Auth Req) |
| **InfluxDB**   | `influxdb.infra.svc.cluster.local`   | 8086  | `admin`            |

---

## 🛠 4. Local Development Connection

To connect your local DB tools (DBeaver, Compass) to these databases, use your SSH tunnel:

```bash
# Example for PostgreSQL
ssh -L 5432:postgresql.infra.svc.cluster.local:5432 root@203.174.22.129
```

---

## 📁 5. Repository & Code

- **Repository**: [https://github.com/AM-Portfolio/am-infra.git](https://github.com/AM-Portfolio/am-infra.git)
- **Deployment Branch**: `develop`
- **Location on VPS**: `/root/am-repos/am-infra`

---

> [!CAUTION]
> **Warning**: Keep this file restricted to the core engineering team. These are administrative credentials.
