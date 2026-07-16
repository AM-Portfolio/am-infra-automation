# 🏗️ AM-Infrastructure: Terraform Architecture & Module Guide

This document is the definitive guide to the Terraform codebase within the `am-infra` ecosystem. It explains **why** the infrastructure is structured the way it is, **what** each module does, and provides a "one-shot" understanding of the day-to-day operations and flow of data.

---

## 📅 The "Why": Layered Operations vs. Monolithic Deployment

In traditional Terraform setups, putting all resources in one massive deployment creates **"Dependency Hell."** If a database fails to deploy, it blocks the monitoring stack; if an identity provider goes down, it crashes the applications that depend on it.

To solve this, our infrastructure uses a **Linear Layered Architecture**. We deploy infrastructure from the ground up, starting with core dependencies, moving to stateful data, and finally to stateless applications and identity layers. 

This guarantees:
1. **Idempotency**: Rerunning a layer won't break upstream or downstream components.
2. **Blast Radius Reduction**: If the `monitoring` layer breaks, the `data-stores` are unaffected.
3. **Clear Dependencies**: Apps cannot start until their data sources exist.

---

## 📚 The Layers (Deployment Sequence)

The Orchestrator (`manage.js`) sequentially applies these layers. Here is the exact order and purpose of each.

### 1. 🏗️ Foundation (`terraform/foundation/`)
* **Purpose:** The bedrock of the cluster. Everything else lives on top of this.
* **What it does:** 
  - Provisions logical `namespaces` (e.g., `infra`, `monitoring`, `identity`).
  - Bootstraps baseline resources like the Traefik Ingress controller and default StorageClasses.
  - Generates cross-cluster base configurations.

### 2. 🗄️ Data Sources / Data Stores (`terraform/data-stores/`)
* **Purpose:** The stateful persistence layer. Data must exist before it is monitored or consumed.
* **What it does:**
  - Deploys **PostgreSQL** (Relational Data), **MongoDB** (Document Data), and **Redis** (Caching/Sessions).
  - Deploys **Kafka** (Event streaming and message brokering).
  - Deploys **InfluxDB** (Time-series data for infrastructure health).
  - Deploys **HashiCorp Vault** (The single source of truth for all secrets).

### 3. 📊 Monitoring (`terraform/monitoring/`)
* **Purpose:** The Observability layer. 
* **What it does:**
  - Deploys the observability stack (Prometheus for metrics, Loki for logs, Promtail for log shipping).
  - Deploys **Grafana** and *automatically links* it to InfluxDB, PostgreSQL, Prometheus, and Loki.
  - Deploys **Headlamp** (`k8s` GUI dashboard) and **Rover** (for Terraform visual state reporting).

### 4. 🛂 Identity (`terraform/identity/`)
* **Purpose:** Centralized Authentication and Single Sign-On (SSO).
* **What it does:**
  - Deploys **Authentik** (our Identity Provider).
  - Sets up OIDC (OpenID Connect) providers so tools like Grafana and Headlamp can use SSO instead of hardcoded admin passwords.
* **Why it's later in the chain:** Authentik *requires* PostgreSQL and Redis to operate. Thus, `data-stores` must come before `identity`.

### 5. 🚀 Platform (`terraform/platform/`)
* **Purpose:** The actual business applications and microservices.
* **What it does:** Deploys custom logic, internal APIs, and portfolio services that consume the databases and utilize Authentik for user management.

### 6. 🌐 Exposer (`terraform/exposer/`)
* **Purpose:** Network mapping and external availability.
* **What it does:** Uses NodePorts, Traefik Routers, and Cloudflare Tunnels to safely open specific internal services (like Vault, Grafana, or Web Apps) to the outside internet or local network (e.g., exposing port 5432 for local DB inspection).

---

## 📦 The Modules Directory: The Reusable Building Blocks

To keep the code DRY (Don't Repeat Yourself), actual resource definitions are stored in `terraform/modules/`. The layers above merely calling these modules by passing environment-specific variables.

### `/modules/core/` (System & Framework Integrations)
These are cluster-wide configuration modules.
* **`authentik/`**: Stands up the core Identity server along with its dedicated cache and database dependencies.
* **`bootstrap/`**: The preliminary configuration that sets up base policies and injects required CRDs (Custom Resource Definitions) into empty clusters.
* **`cloudflare/`**: Connects the cluster to Cloudflare via Tunnels and manages DNS records.
* **`db-users/`**: **Critical Module.** Instead of hardcoding database users, this module auto-generates credentials for any new app, creates the PostgreSQL/MongoDB roles, and safely injects those credentials into **HashiCorp Vault**.
* **`github-runner/`**: Provisions self-hosted GitHub Actions runners inside the cluster.
* **`namespaces/`**: Creates the logical Kubernetes namespaces like `infra`, `monitoring`, etc.
* **`port-exposer/`**: Specifically manages the Kubernetes `Service` definitions that map internal cluster IPs to external nodes.
* **`traefik/`**: Defines the Ingress routes (how domain names like `grafana.munish.org` map to internal pods).

### `/modules/apps/` (Container Workloads / Services)
These modules define the actual container deployments and stateful applications.
* **`grafana/`**: Deploys Grafana and auto-provisions sidecars to load dashboards (`dashboards.tf`) and data sources (`datasources.tf`).
* **`headlamp/`**: A beautiful, read-only Kubernetes cluster visualizer.
* **`vault/`**: Deploys HashiCorp Vault. It includes complex bootstrap logic to auto-unseal itself and write its master keys back as raw Kubernetes secrets so the scripts can retrieve them.
* **`rover/`**: A Terraform visualizer running as a pod, mapping `terraform.tfstate` into an interactive tree diagram.
* **`postgresql/`, `mongodb/`, `kafka/`, `redis/`, `influxdb/`**: Standardized, production-mimicking deployments of these data stores using official images and customized persistence mappings (HostPaths) to ensure data outlives pod failures.

---

## 🛠️ The Automation Wrapper (Scripts)

You should almost **never** run `terraform apply` manually.

### `/scripts/orchestration/manage.js`
This is your **"Hybrid Orchestrator"**. Since the infrastructure is broken into pieces, this Node.js script figures out the correct dependencies.
* **What it does:** 
  1. Synchronizes `process.env` with `infrastructure-secrets`.
  2. Maps friendly names to Terraform modules (e.g., `-p monitoring` runs the entire monitoring layer, `-a mongodb` isolates just the MongoDB module).
  3. Executes `terraform init / plan / apply` safely in the correct sub-directories.

### Example Day-to-Day Workflow
1. **Stand up the whole cluster locally:**
   ```bash
   pwsh scripts/orchestration/infra-up.ps1
   ```
2. **You want to change a Grafana Dashboard:**
   - Edit `terraform/monitoring/dashboards.tf`.
   - Run: `node scripts/orchestration/manage.js apply -p monitoring`.
3. **You need to rotate database secrets:**
   - Run: `python scripts/security/manage_secrets.py --sync`.
   - Vault and the databases are updated transparently via Terrafrom.

---

## 🧭 Summary

1. **Modules (`/modules`)** define *how* things are built.
2. **Layers (`/foundation`, `/data-stores`, etc.)** define *when* and *where* they are deployed.
3. **Scripts (`/scripts`)** automate the complex glue holding the terraform states and secrets together.
