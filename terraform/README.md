# Terraform Layered Infrastructure

This directory contains the Infrastructure as Code (IaC) configuration representing the core of the `am-infra` ecosystem. We utilize an industry-standard **Layered Architecture**. Instead of a monolithic setup where deploying one component risks evaluating the entire system, our infrastructure is broken into isolated layers with dedicated local state files.

## Layer Execution & Auditing

> [!WARNING]
> DO NOT run raw `terraform apply` manually in the directories unless you know what you are doing.

To prevent configuration mistakes and to ensure a persistent audit trail, we orchestrate all Terraform deployments natively via our Python wrapper.
This automatically injects dynamic `.env.infra` properties, cross-environment tokens (`GITHUB_PAT`, `VPS_PASS`), and routes logs directly to the persistent storage.

### Wrapper Command
```powershell
python scripts/infra.py tf [plan|apply|destroy] --layer [LAYER_NAME] --env [ENVIRONMENT]
```

**Example (Deploying the Runner on the VPS):**
```powershell
python scripts/infra.py tf apply --layer apps --env hostbet-vps
```
*Note: Every execution outputs a timestamp-structured log in `logs/terraform/terraform-YYYY-MM-DD.log` so you know exactly "what is happening and where".*

## The Layers

The infrastructure is broken out linearly. When provisioning from scratch, these layers should be applied sequentially.

| Layer | Directory | Description |
| :--- | :--- | :--- |
| **Core** | `/core` | Provisions all base Kubernetes structures and namespaces (`infra`, `monitoring`, `github-actions`, etc.) that downstream layers rely on. |
| **Security** | `/security` | Randomly generates and safely injects Kubernetes secrets for external DBs, Vault, Kafka, and the Runner. Provisions Hashicorp Vault instances. |
| **Data** | `/data` | Deploys stateful payloads—MongoDB, PostgreSQL, Redis, InfluxDB, Kafka, and Zookeeper into the cluster by injecting secure environments into raw YAML manifests. |
| **Monitoring** | `/monitoring` | Installs Prometheus, Grafana, and Promtail/Loki for full cluster observability and visualization. |
| **Apps** | `/apps` | Provisions dynamic workloads like the Traefik ingress, Headlamp dashboard, and orchestrates the custom GitHub Actions Runner Docker-in-Docker setup directly on the VPS node. |

## Core Implementation Features

### 1. Common Base (`_common/`)
To uphold the DRY (Don't Repeat Yourself) principle, `variables.tf`, `providers.tf`, and `env_config.tf` live in `_common/`. The deployment wrapper seamlessly pulls these dependencies when evaluating any target layer.

### 2. Dynamic Environment Configuration
Our setup eschews hardcoded values in favor of dynamic parsing natively via `env_config.tf`.
- **`.env.infra` parsing**: Terraform dynamically reads `am-infra/.env.infra` using regex to extract values like ports (e.g., `PORT_MONGO`). 

### 3. Native File Templating
Instead of relying only on native CRDs (which can be flaky), we utilize `gavinbunney/kubectl` to aggressively template Raw YAML definitions from the `../k8s` directory. We intercept `.env` defaults or dummy passwords dynamically rendering Terraform's secure password outputs directly as Native specs.
