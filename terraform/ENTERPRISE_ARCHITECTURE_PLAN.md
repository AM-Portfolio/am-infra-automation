# Comprehensive Enterprise Terraform Architecture Plan

This plan outlines a complete transformation of your infrastructure repository. We are migrating from a horizontally segmented architecture into a vertically sliced, modular, enterprise-ready system. This ensures that every resource dynamically and safely handles state, prevents data loss under any scenario, and seamlessly bridges local and remote configurations.

---

## 🏗️ PART 1: What Currently Exists

Here is the exhaustive map of everything currently present in your infrastructure that will be restructured:

### 1. Data Layer (`terraform/data` & `k8s/`)
Currently deploys raw, hardcoded Kubernetes manifests via loop reading flat files in `/k8s/`:
* **MongoDB**: Hardcoded YAML manifest.
* **Apache Kafka & Zookeeper**: Hardcoded YAML manifests.
* **PostgreSQL**: Hardcoded YAML manifests.
* **Redis**: Hardcoded YAML manifests.
* **InfluxDB**: Hardcoded YAML manifests.

### 2. Identity Layer (`terraform/identity`)
Currently bundled into large files (`app_*.tf` and `outposts.tf`), managing Authentik:
* **Core Authentik**: Server, Outposts, Database endpoints.
* **OIDC Applications**: Headlamp, Vault, Grafana (Currently basic mappings, lacking generic group RBAC sync).
* **Proxy Applications**: Traefik Dashboard, Kafka UI, InfluxDB, Mongo Express, pgAdmin, Redis Commander/Insight.
* **Configuration Sync**: Secrets synced to Vault mapping client IDs and hashes.

### 3. Gateway Layer (`terraform/gateway`)
Currently contains IngressRoutes scattered separately from their actual applications:
* **Routes**: Headlamp, Vault, Grafana, Traefik, Kafka UI, MongoDB, InfluxDB.
* **Middlewares**: `force-https-proto`, `authentik-auth`, `global-cors`, and app-specific tokens.

### 4. Security & Monitoring (`terraform/security`, `terraform/monitoring`)
* **Security**: Hashicorp Vault (Helm deployment), Vault Auth, OIDC configs, and K8s Secrets.
* **Monitoring**: Prometheus/Grafana (Helm), Headlamp, Rover. 

### 5. Weaknesses in the Current State
* **Scattered Configuration**: Modifying Kafka requires touching `data`, `gateway`, and `identity` separately.
* **Hardcoded Legacy YAMLs**: Relying on flat files in `k8s/` prevents true parameterized infrastructure management. It lacks the modularity of native Terraform configs.
* **Brittle Authentication Scaling**: OIDC integrates 1-2 accounts, but adding new users requires manual role assignments inside Grafana/Vault. It lacks automated OIDC Group/Role syncing.
* **Data Loss Vulnerability**: Running a `terraform destroy` or recreation accidentally deletes Vault's PVC or MongoDB's PVC because there are no explicit lifecycle locks preventing data purging.

---

## 🚀 PART 2: What Will Change (The Enterprise Vertical Slice)

We will abandon the horizontal layer approach. Every application will exist inside `terraform/modules/apps/{app_name}` and will define all of its own `resources`, `data`, `providers`, `variables`, `locals`, and `outputs`.

### Structural Transformation
We will create a multi-environment, vertical-sliced architecture:

```text
terraform/
├── environments/
│   ├── preprod/
│   │   ├── main.tf             (Calls all app modules, passes environment variables)
│   │   ├── backend.tf          (Configures the Kubernetes Remote State)
│   │   ├── provider.tf 
│   │   └── variables.tf
├── modules/
│   ├── apps/
│   │   ├── kafka/              (All-in-one vertical slice)
│   │   │   ├── main.tf         (Deploys Kafka & UI manifests)
│   │   │   ├── identity.tf     (Authentik Proxy, Auth flow)
│   │   │   ├── gateway.tf      (Traefik Route + Middlewares)
│   │   │   ├── data.tf         (References to k8s/kafka/*.yaml)
│   │   │   ├── variables.tf
│   │   │   ├── locals.tf       (Dynamically computes ports/urls based on env)
│   │   │   └── outputs.tf
│   │   ├── mongodb/            (Same vertical structure)
│   │   ├── vault/              (Helm, Identity OIDC, Gateways + Prevent Destroy)
│   │   ├── influxdb/
│   │   ├── grafana-observability/ (Grafana + Prometheus + Loki + Promtail Stack)
│   └── core/
│       ├── traefik-proxy/      (Core networking proxy + Dynamic Custom Directory Sync)
│       ├── authentik-server/   (Core identity)
│       └── base-namespaces/    (Core cluster namespaces configuration)
```

## Advanced Features & Data Prevention

1. **Pure Terraform Migration (Zero K8s YAML)**
   * We will completely abandon the static files in `k8s/` (e.g., `k8s/mongodb/*.yaml`). Everything will be rebuilt using native `helm_release` modules or native `kubernetes_deployment` resources inside Terraform.
   * **Why?** This ensures full parameterized control, allowing you to scale replicas or change resource limits universally from a single `variables.tf` instead of manually editing separated YAML code.

2. **Enterprise OIDC Role/Group Syncging**
   * Currently, adding a user to Authentik does not automatically give them the correct permissions inside Grafana or Vault.
   * We will implement **Generic Group Mappings** via Authentik tokens. Terraform will define `Admin` and `Viewer` groups in Authentik and dynamically map these into the `grafana` and `vault` Terraform helm values. Any user you add in the future will seamlessly inherit perfect SSO dashboard access instantly.

3. **Dual State Synchronization (Local + Remote VPS)**
   * **Remote Backend**: We will configure Terraform to use the `kubernetes` backend. It will store the `.tfstate` file as an encrypted Secret inside the VPS Kubernetes cluster. This means GitHub Actions and your local machine are 100% physically synced to the exact same locked file.
   * **Local Backup Module**: We will use a `local_file` resource hooked to an output that guarantees a physical `terraform_state_backup.json` or credential copy is saved on your local Windows directory immediately upon every successful apply, ensuring you always have offline physical access to credentials.

4. **Credentials Redundancy (K8s Secrets + Physical Files)**
   * Randomly generated passwords (e.g., Vault OIDC secrets, Auth tokens) will be pushed explicitly to:
     1. K8s Secrets (`kubernetes_secret` resource)
     2. Hashicorp Vault (`vault_generic_secret` resource)
     3. Local File System (`local_sensitive_file` resource mapped to `infrastructure-secrets/latest/`)

5. **Absolute Data Loss Prevention (Retention Policies)**
   To ensure absolutely zero data loss (e.g., your Vault Keys or MongoDB records) during a Terraform recreation or accidental delete, we will apply two Enterprise lock mechanisms:
   * **Terraform Level**: Adds `lifecycle { prevent_destroy = true }` and `ignore_changes = [metadata.annotations]` to all StatefulSets, PVCs, and Helm Charts.
   * **Kubernetes Level**: Patches all Persistent Volumes (PV/PVCs) generated by your applications to use `.spec.persistentVolumeReclaimPolicy = Retain`. If Terraform attempts to delete MongoDB, it is forced to leave the hard drive volume untouched. When it reconstructs MongoDB, it inherently mounts the exact same disk without breaking any data flows.

---

## 🛠️ PART 3: Step-by-Step Implementation Plan

1. **Step 1: State Backup & Protection Lock**
   * Manually commit the current local `terraform.tfstate` contents to a locked local backup file.
   * Apply Helm parameter patches to Vault, Kafka, and MongoDB explicitly setting PVCs to `Retain` before any moving happens.

2. **Step 2: Module Construction (The Vertical Slices)**
   * Scaffold `terraform/modules/apps/*` and `terraform/modules/core/*`.
   * Distribute existing configurations (`data.tf`, `variables.tf`, `locals.tf`, `outputs.tf`) into their respective vertical module directories (Kafka, Mongo, Traefik).

3. **Step 3: Environment Bootstrapping**
   * Create `terraform/environments/preprod/main.tf`.
   * Initialize module calls passing the correct VPS environment variables and domain dependencies.

4. **Step 4: The Crucial State Cutover**
   * Utilize `terraform state mv` commands script to translate the old horizontal state addresses (e.g., `module.gateway.ingress_route_kafka`) to the new vertical addresses (e.g., `module.kafka.ingress_route`). **This ensures Terraform touches exactly zero real resources during the transition.**

5. **Step 5: Backend Migration (Remote + Local Sync)**
   * Write `backend.tf` assigning Kubernetes as the state backend.
   * Run `terraform init -migrate-state` to push the successfully factored state up to the VPS cluster.
   * Execute `terraform apply` to validate the new structure and create the local credential redundancy files.
