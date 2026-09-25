# TODO — kind-fleet-clusters

**Agent playbook:** skill **`am-kind-fleet`** in `amctl/ai-catalog/skills/platform/am-kind-fleet/` (install with `am ai sync` / `am ai install` when ready — review skill first). Checkboxes here remain SoT for multi-env / laptop history.

**Prod track SoT:** [`PROD_DEPLOY.md`](PROD_DEPLOY.md) + [`prod/`](prod/) (VPS1 phase-wise Implement + Test — all unchecked until executed).

Pack: `docs/kind-fleet-clusters/`. Resume from the first unchecked **Test** item (for **prod**, open `prod/` first).

**G26 (once, after DBs exist):** reach everything at `*.asrax.in`. Never `localhost`, `127.0.0.1`, `host.docker.internal`, or a Docker-host / bridge IP in Vault, Helm, Traefik, OIDC, or MCP. Same-host stores: **DNS-only** A record → that host’s private/WG IP (not orange-cloud).

**G27 — Restrict test rules (always):**

1. Test **only** via the env domain (`https://…asrax.in` or DNS-only store host).
2. **Never** `kubectl port-forward` to prove a store or UI.
3. **Never** `localhost`, Docker host, or a raw NodePort in a Test checkbox.
4. Phase 2: **Edge first** (Traefik + tunnel). Then stores. Then IngressRoutes. Then **domain-test** (empty connect). **Then** seed. **Then** domain-test again. No seed until the pre-seed Test is green.
5. HTTPS tests must go Cloudflare → tunnel → **Traefik** → Service. A tunnel origin that bypasses Traefik (direct Service) is a **fail** on prod/DR.

**Every phase:** Implement (full list below) → **Test (this phase)** → **Test (grown)**. Fail = stay.

**Loop:** Prereq → Implement → `am ai sync` + `am ai mcp-sync --ide cursor --host-launchers` (when host launchers like Cloudflare/Keycloak/Argo are needed) → Test. Platform stack verify = **Phase 3e**. VPS Kind only after Phase 5. Day-2 = `am-ops`. Kind create/stop = G1.

**Phase P connections (local + every VPS + Cloudflare MCP) → Phase 0 dump → Phase C clean four → four tracks together.** Do **not** Execute until this pack is user-reviewed. Do **not** clean until Phase P + Phase 0 Tests are green.

### Sequence map (TOC)

| Order | Phase | Notes |
|-------|-------|-------|
| 1 | [Phase P](#phase-p--start-and-test-all-connections-first) | Connections first |
| 2 | [Phase 0](#phase-0--protect-data) | Protect data (fleet — not ZT-P0) |
| 3 | [Phase C](#phase-c--clean-four-hosts) | Clean hosts |
| 4 | [Phase 1](#phase-1--terraform-kind-module) | Kind TF module |
| 5 | [Phase 2](#phase-2--infra--seed-dbs-am--infra) | Infra + seed |
| 6 | [Phase 3a–3e](#phase-3a--identity-am--platform) | Identity / platform |
| 7 | [Phase 4](#phase-4--apps-vault--am-gitops-waves-4a4g) | Apps waves |
| 8 | [Phase 5](#phase-5--vps-connect--security-before-any-vps-kind) | VPS security |
| 9 | [Phase ZT](#phase-zt--zero-trust--identity-admin) | Zero-trust + Identity Admin (pointers) |
| 10 | [Phase 6–9](#phase-6--dr--replica-users-still-on-vps1) | DR / failback |
| 11 | [Phase 10](#phase-10--sso-prove) | SSO prove (ZT-P1 enforce sync) |
| 12 | [Phase 11](#phase-11--vps2-obs--grafana-parallel) | VPS2 obs (Alloy Access token) |
| 13 | [Phase 12](#phase-12--scheduled-failover-drill) | Failover drill |

Detail: [`../ZERO_TRUST_ACCESS.md`](../ZERO_TRUST_ACCESS.md) · [`am-platform/docs/features/enterprise-identity-admin-rbac.md`](../../../am-platform/docs/features/enterprise-identity-admin-rbac.md)

---

## What we use (locked — do not invent substitutes)

### Hosts / env tokens


| Host | Env | Connection (from [VPS/.env](../../../VPS/.env), **IPs only**) | Clusters | TF state |
| ---- | --- | ------------------------------------------------------------ | -------- | -------- |
| Laptop | `dev` lab (optional) | Docker on this machine | `am-dev-*` (product); platform prefers VPS2 | `~/.asrax/tfstate/dev/` |
| VPS1 Contabo | `prod` | `VPS_IP` | `am-prod-infra` / `apps` / `platform` (2-node) | `/data/am-state/terraform/prod/` |
| VPS2 | **ops / shared platform** | `VPS_2_IP` | `am-obs` + platform tools; Vault **`apps/data/dev` SoT** | `/data/am-state/terraform/obs/` (+ platform) |
| VPS3 | `dr` | `VPS_3_IP` | `am-dr-infra` / `apps` / `platform` (1-node) | `/data/am-state/terraform/dr/` |

**Connection file:** [VPS/.env](../../../VPS/.env) (gitignored). Use `VPS_IP` / `VPS_2_IP` / `VPS_3_IP` and kube name `VPS_KUBECONFIG`. **Never** copy `VPS_*_PASSWORD`, `VAULT_TOKEN`, or unseal keys into this pack or git. Legacy `VAULT_ADDR=http://localhost:8201` in that file is **not** the new cluster addr (G26).

### Cluster names (business tokens — never “always preprod”)

Formula: `cluster_role == "obs" ? "am-obs" : "am-${env}-${cluster_role}"`. Env = `dev|prod|dr|obs` only. People may say “local” for the laptop — that is still `dev`.

| Business | Host | Kind names | App NS | Agents NS | Vault prefix | `am deploy --env` | Kubeconfig |
| -------- | ---- | ---------- | ------ | --------- | ------------ | ----------------- | ---------- |
| Development (lab) | laptop (optional) | `am-dev-infra` / `apps` / `platform` | `am-apps-dev` | `am-agents-dev` | **SoT → VPS2** `apps/data/dev/` | `dev` | `~/.asrax/kubeconfig.am-dev-<role>.yaml` |
| Production | VPS1 | `am-prod-infra` / `am-prod-apps` / `am-prod-platform` | `am-apps-prod` | `am-agents-prod` | `apps/data/prod/` | `prod` | `/data/am-state/kubeconfig.am-prod-<role>.yaml` · `kind-am-prod-<role>` |
| Disaster recovery | VPS3 | `am-dr-infra` / `am-dr-apps` / `am-dr-platform` | `am-apps-dr` | `am-agents-dr` | `apps/data/dr/` | `dr` | `/data/am-state/kubeconfig.am-dr-<role>.yaml` · `kind-am-dr-<role>` |
| Ops + platform hub | VPS2 | `am-obs` (+ platform) | — (no product apps) | — | **`apps/data/dev/` SoT** + obs | `obs` | `/data/am-state/kubeconfig.am-obs.yaml` · `kind-am-obs` |

**VPS2 hub detail:** [VPS2_DEV_PLATFORM.md](VPS2_DEV_PLATFORM.md) — DBs + Grafana/OpenProject/Lago/Langfuse/… credentials.

### Env plug-and-play (kind-fleet + GitOps)

- **One knob:** `local.env` / script `-Env dev|prod|dr`. Shared names: [`terraform/kind-fleet/fleet-env.ps1`](../../terraform/kind-fleet/fleet-env.ps1) + TF module [`modules/core/fleet-naming`](../../terraform/modules/core/fleet-naming).
- **New env:** copy `kind-fleet/{env}/` stack, set `local.env`, run `setup-g25-vault-auth.ps1 -Env <env>` and `fresh-redeploy.ps1 -Env <env> -Force`.
- **GitOps:** `{env}/values-overlays/fleet-common.yaml` (Vault HTTPS + NS/uiHost). Image tags only in `{env}/image-tags/`. Agents under `{env}/agents/` → `am-agents-{env}`; product under `{env}/apps/` → `am-apps-{env}`.
- **Gates:** `am-gitops/scripts/assert-vault-https.ps1` — reject `http://vault` and inline Application `tag:` under `values:`.

**Refuse to create / apply / `--env`:** `am-preprod`, `am-local`, `kind-am-preprod`, `kind-am-local`, `am-apps-preprod`, `am-apps-local`, `--env local`, `--env preprod`, `hostbet-vps`. Do **not** apply `terraform/{foundation,identity,platform,vault,monitoring}/{local,preprod}` for this fleet. New entrypoints only: `terraform/kind-fleet/{dev,prod,dr,obs}/`.

**`preprod` stays only as:** Vault **key-name** source (`apps/data/preprod/...` — copy keys, rewrite domains, never values); historical note that Contabo Kind used to be named `am-preprod` (already deleted in Phase C); existing CF tunnel `asrax-preprod` / PP hosts — **out of scope**.

**Legacy still in repo (do not copy these names into the fleet):** [am-infra/k8s/kind-config.yaml](../../../am-infra/k8s/kind-config.yaml) `name: am-preprod`; [terraform/foundation/cluster.tf](../../terraform/foundation/cluster.tf) `am-${environment}` with only `local`/`preprod` stacks. Phase 1 module **computes** the Kind name from `env` + `cluster_role` — no free-form `cluster_name` that can be `am-preprod`.


### Repos / CLI


| Use                                     | What                                                              |
| --------------------------------------- | ----------------------------------------------------------------- |
| Kind + Terraform + Vault wiring         | `am-infra-automation`                                             |
| Kind YAML / Traefik / console manifests | `am-infra`                                                        |
| GitOps destinations                     | `am-gitops`                                                       |
| Deploy apps                             | `amctl` (`am deploy --env dev|prod|dr`)                     |
| MCP catalog                             | `~/.asrax` + `am ai sync` + `am ai mcp-sync`                      |
| Seed data                               | `F:\am-repos\asrax-db-backups\*\latest` + `BACKUP_OK.txt`         |
| Disaster copy                           | Cloudflare **R2** (PG, Mongo, Vault, MinIO, PKI, tfstate)         |
| DNS / tunnels / LB                      | Cloudflare MCP (`user-cloudflare`) — one **cloudflared** per host |
| Replica link                            | **WireGuard** VPS1↔VPS3 (PG :5432 + Mongo :27017 only)            |
| First AM waves (Phase 4)                | Argo from `am-gitops` `dev/` (then `dr/` / `prod/`) — 4a–4g      |
| Product shell                           | `am-modern-ui` + gateway (`am-asrax-proxy` / `am-gateway`)        |


### Infra on `am-*-infra` (namespace `infra` + `vault`)


| Component   | Image / product                          | Domain after seed (dev example)        | Notes                                                              |
| ----------- | ---------------------------------------- | -------------------------------------- | ------------------------------------------------------------------ |
| PostgreSQL  | Postgres (Kind chart / current am-infra) | `postgres-dev.asrax.in` DNS-only     | Seed + G20 primary/standby                                         |
| MongoDB     | Mongo                                    | `mongo-dev.asrax.in` DNS-only        | Seed + replica set                                                 |
| Redis       | Redis                                    | `redis-dev.asrax.in` DNS-only        | Seed only                                                          |
| Kafka       | Kafka                                    | `kafka-dev.asrax.in` DNS-only        | `advertised.listeners` = this domain                               |
| InfluxDB    | Influx                                   | `influx-dev.asrax.in` DNS-only       | Seed                                                               |
| MinIO       | MinIO                                    | `minio-dev.asrax.in` (API + console) |                                                                    |
| Vault       | HashiCorp Vault                          | `vault-dev.asrax.in`                 | **injector.enabled=false**. KV mount `apps`. Policy `am-apps-read` |
| Traefik     | Traefik                                  | `traefik-dev.asrax.in`               | Edge on apps/infra as today                                        |
| cloudflared | Cloudflare tunnel                        | —                                      | One per host                                                       |


Prod drops `-dev` on the main names (`vault.asrax.in`, `minio.asrax.in`). DR uses `-dr`.

### Vault access for apps (G25) — what is used


| Piece              | Exact name                                                                                                     |
| ------------------ | -------------------------------------------------------------------------------------------------------------- |
| App ServiceAccount | `am-backend-sa` in `am-apps-<env>` (`automountServiceAccountToken: true`)                                      |
| Image pull         | `regcred` + `github-registry-secret` on that SA                                                                |
| Reviewer SA        | `vault-auth-reviewer` in apps `kube-system` + ClusterRoleBinding `system:auth-delegator`                       |
| Cluster CSI        | secrets-store-csi-driver + **vault-csi-provider** DaemonSet on **apps** cluster                                |
| Vault auth mount   | `auth/kubernetes-apps` (not the infra-cluster default mount)                                                   |
| Vault role         | `am-backend-role` bound to `am-backend-sa` / `am-apps-<env>`                                                   |
| Policy             | `am-apps-read` on `apps/data/<env>/*`                                                                          |
| Helm               | `global.vault.serviceAccountName=am-backend-sa`, `global.vault.csi.enabled=true`, `vault.role=am-backend-role` |
| **Not used**       | Vault Agent Injector, per-pod Vault sidecar, `localhost` Vault addr                                            |


### Platform on `am-*-platform`


| Component    | What                                                                                                                      |
| ------------ | ------------------------------------------------------------------------------------------------------------------------- |
| Keycloak     | Realm `am-realm`. Roles `am-admin`, `am-ops`, `am-viewer`, `am-user`. Domain `auth-dev.asrax.in` (prod `auth.asrax.in`) |
| Argo CD      | `enable_argocd=true`, `prune: false`. Domain `argocd-dev.asrax.in`                                                      |
| Temporal     | Helm on platform; user `temporal` on PG `platform` (schemas `temporal` + `temporal_visibility`); UI `temporal-<env>.asrax.in` |
| Lago         | Billing engine in NS `billing`; dedicated PG DB `lago` (user `lago`, CREATEDB); UI `lago-<env>.asrax.in`. **Not** `am-subscription` |
| n8n          | User `n8n` on PG `platform`. UI `n8n-<env>.asrax.in`                                                                      |
| GrowthBook   | User `growthbook` on Mongo `platform`. UI `growthbook-<env>.asrax.in`                                                      |
| OpenProject  | User `openproject` on PG `platform`. UI `openproject-<env>.asrax.in`                                                       |
| LiteLLM      | User `litellm` on PG `platform`. NS `am-ai`. UI `litellm-<env>.asrax.in`                                                   |
| Langfuse     | User `langfuse` on PG `platform` + Redis ACL + MinIO. ClickHouse in-module. UI `langfuse-<env>.asrax.in`                   |
| **Novu**     | Push / notification engine in NS `notification`; Mongo DB `novu` + Redis `/2` on infra stores; UI `novu-<env>.asrax.in`. Helm at Phase **3d**. **Not** `am-notification` (apps Phase 4+) |
| oauth2-proxy | In front of UIs with no native OIDC                                                                                       |
| **Not used** | Authentik, kagent                                                                                                         |
| **Sizing**   | Infra + platform CPU/mem tables → [`docs/kind-fleet-resources/SIZING.md`](../kind-fleet-resources/SIZING.md) (TF modules = SoT) |


### Consoles (G24) — product + domain + OIDC client


| UI                | Product                                     | Local host                                               | Keycloak client |
| ----------------- | ------------------------------------------- | -------------------------------------------------------- | --------------- |
| modern-ui         | `am-modern-ui`                              | `am-dev.asrax.in`                                      | `am-modern-ui`  |
| gateway           | `am-gateway` / asrax-proxy                  | same host / API paths                                    | `am-gateway`    |
| Keycloak          | Keycloak                                    | `auth-dev.asrax.in`                                    | (issuer)        |
| MinIO console     | MinIO                                       | `minio-dev.asrax.in`                                   | `minio`         |
| Grafana           | Grafana                                     | `grafana.asrax.in` (bare; Kind hub → VPS2 Phase 11) | `grafana`       |
| Argo CD           | Argo CD                                     | `argocd-dev.asrax.in`                                  | `argocd`        |
| Headlamp          | Headlamp                                    | `headlamp-dev.asrax.in`                                | `headlamp`      |
| Kafka UI          | `provectuslabs/kafka-ui`                    | `kafka-ui-dev.asrax.in`                                | `kafka-ui`      |
| Postgres UI       | pgAdmin                                     | `pgadmin-dev.asrax.in`                                 | `pgadmin`       |
| Mongo UI          | mongo-express                               | `mongo-express-dev.asrax.in`                           | `mongo-express` |
| Redis UI          | RedisInsight / Commander (current am-infra) | `redis-ui-dev.asrax.in`                                | `redis-ui`      |
| Vault UI          | Vault UI                                    | `vault-dev.asrax.in`                                   | `vault-ui`      |
| Influx UI         | Influx                                      | `influx-dev.asrax.in`                                  | `influx-ui`     |
| Temporal Web      | temporal-web                                | `temporal-dev.asrax.in` (prod `temporal.asrax.in`)     | `temporal-web`  |
| Lago              | Lago API + front (NS `billing`)             | `lago-dev.asrax.in` (prod `lago.asrax.in`)             | `lago`          |
| n8n               | n8n                                         | `n8n-dev.asrax.in`                                     | `n8n`           |
| GrowthBook        | GrowthBook                                  | `growthbook-dev.asrax.in`                              | `growthbook`    |
| OpenProject       | OpenProject                                 | `openproject-dev.asrax.in`                             | `openproject`   |
| LiteLLM           | LiteLLM                                     | `litellm-dev.asrax.in`                                 | `litellm`       |
| Langfuse          | Langfuse                                    | `langfuse-dev.asrax.in`                                | `langfuse`      |
| Novu              | Novu (push)                                 | `novu-dev.asrax.in`                                    | `novu`          |
| Traefik dashboard | Traefik                                     | `traefik-dev.asrax.in`                                 | `traefik`       |

**OIDC test personas** (passwords in Vault `apps/data/<env>/infra/keycloak-test-users` only):

| Username | Roles | Intent |
|----------|-------|--------|
| `am-admin-test` | `am-admin`, `am-ops` | One admin credential — SSO to every wired G24 console |
| `am-user-test` | `am-user` | One user credential — readonly / limited on admin consoles |


### AM apps waves (Phase 4a–4g) — Vault = Terraform; workloads = Argo from main


| Wave | Deploy | How | NS |
| ---- | ------ | --- | -- |
| **4a** | Apps cluster + Vault G25 only (no product pods) | **`terraform apply`** (`vault-apps` + CSI auth) | `am-apps-<env>` (+ agents NS SA) |
| **4b** | Retarget `am-gitops` `dev/`; scaffold missing `dr/` | Git + Argo register | Argo |
| **4c** | `am-gateway`, `am-api-gateway` / `am-asrax-proxy`, `am-ai-gateway`, `am-modern-ui` | **Argo sync from `main`** | `am-apps-<env>` / `am-agents-<env>` |
| **4d** | `am-identity` (+ subscription/notification if needed for login) | **Argo sync from `main`** | `am-apps-<env>` |
| **4e** | `am-market-data` | **Argo sync from `main`** | `am-apps-<env>` |
| **4f** | `am-portfolio` → `am-trade-management-service` → `am-document-processor` → news/analysis | **Argo sync from `main`** | `am-apps-<env>` |
| **4g** | **All remaining** `dev/apps` + `dev/agents` (+ `apps-full`); **Postman MCP** closout | **Argo sync from `main`** | `am-apps-<env>` / `am-agents-<env>` |
| **Gate** | Phase 4 done when 4g Postman `runCollection` core folders green on AM-dev | — | — |

Helm / `am deploy` = break-glass only. SoT: [am-gitops/dev/apps](../../../am-gitops/dev/apps) + [dev/agents](../../../am-gitops/dev/agents). Default Application `targetRevision` = **`main`**. Vault CSI overlay pattern: [preprod vault-https-preprod.yaml](../../../am-gitops/preprod/values-overlays/vault-https-preprod.yaml) → fleet `vault-<env>.asrax.in` + K8s auth (not JWT-to-prod). Vault paths = **Terraform**, not Argo.


### Vault paths written (keys only, values rewritten)

From working preprod [values.preprod.yaml](../../../am-market/am-market-data/helm/values.preprod.yaml) + other service mappings:

- `apps/data/<env>/infra/postgres`
- `apps/data/<env>/infra/mongodb`
- `apps/data/<env>/infra/redis`
- `apps/data/<env>/infra/kafka`
- `apps/data/<env>/infra/influxdb`
- `apps/data/<env>/infra/observability`
- `apps/data/<env>/services/<service>` for each wave (start with `am-market-data`, `am-identity`, `am-gateway`, …)

`<env>` = `dev` | `prod` | `dr`. Copy **key names**. Rewrite hosts/URIs/issuers/redirects to that env’s `*.asrax.in`.

### MCP used to verify

Vault, MinIO, Kafka, Keycloak, Argo CD, Cloudflare, Grafana, Prometheus. Env files: `~/.asrax/credentials.d/dev.env` | `prod.env` | `dr.env` — domain URLs only.

---

## Pack (docs only)

- [x] `PLAN.md`
- [x] `TODO.md`
- [x] `architecture.drawio`
- [x] `GAPS.md`
- [ ] **User reviewed** and confirmed Execute

---

## Phase P — Start and test all connections first

Read IPs from [VPS/.env](../../../VPS/.env). **Start nothing Kind yet.** Prove laptop (local/dev) + all three VPS + Cloudflare MCP. Fail here, not in Phase 4.

### Implement

- [x] Load `VPS/.env` on the laptop (IPs only; no secrets printed)
- [x] Laptop local/dev: Docker running; `~/.asrax` present; `am ai status` OK; host launchers restored with `am ai mcp-sync --ide cursor --host-launchers`
- [x] Laptop: SSH key that can reach `VPS_IP` / `VPS_2_IP` / `VPS_3_IP` (prefer key; passwords stay in `.env` only)
- [x] Start/test SSH to **VPS1** (`VPS_IP`) — prod
- [x] Start/test SSH to **VPS2** (`VPS_2_IP`) — ops / platform hub (obs + credentials)
- [x] Start/test SSH to **VPS3** (`VPS_3_IP`) — dr
- [x] Cloudflare MCP (`user-cloudflare`): Cursor `mcp_auth` as `admin@asrax.in` — now sees **`asrax.in`**
- [x] Cloudflare: zone `asrax.in` listable via MCP
- [x] Cloudflare: tunnels listable via MCP — `asrax-dev-tunnel` (down), `asrax-preprod-tunnel` (healthy), `asrax-prod-tunnel` (down)
- [x] Cloudflare: R2 listable via MCP — bucket `asrax-disaster` created (WEUR)

### Test (this phase) — all of these, no port-forward

- [x] Laptop Docker `docker info` OK (local/dev track) — started Desktop; Server 29.2.1
- [x] SSH session to VPS1 (`VPS_IP`) OK — key as `root`, host `asrax` (`am-vps1`)
- [x] SSH session to VPS2 (`VPS_2_IP`) OK — key as `root`, host `hal-server-864702` (`am-vps2`)
- [x] SSH session to VPS3 (`VPS_3_IP`) OK — key as `root`, host `hal-server-867307` (`am-vps3`)
- [x] Cloudflare MCP: `asrax.in` + 3 tunnels
- [x] **Gate:** Phase P green (SSH + Docker + MCP zone/tunnels/R2)

### Test (grown)

- [ ] *(Phase P only — this list grows after dump)*

---

## Phase 0 — Protect data

### Implement

- [x] Prereq: **Phase P Test green**
- [x] Prereq: `F:\am-repos\asrax-db-backups` present — `BACKUP_OK.txt` under mongo/postgres/redis/influx `latest` (postgres/prod/latest missing; shared + mongo prod OK)
- [x] Prereq: R2 bucket reachable — `asrax-disaster`
- [ ] Implement daily disaster dump on **current primary** → R2: **blocked** — VPS1 `am-preprod` has empty `infra-prod` / `vault` / `am-apps-prod` (no pods, no PVCs). Socat proxies only. No `/data/am-state` tfstate. Live PG/Mongo/Vault dump not possible
- [x] Laptop pull of latest daily prefix — MCP lists `prod/2026-09-23/MANIFEST.json` (marker only; no live dump objects)
- [x] Keep `asrax-db-backups` as the **seed** source (separate from R2 disaster)

### Test (this phase)

- [x] R2 MCP lists today’s prefix `prod/2026-09-23/`
- [x] Laptop has `asrax-db-backups` `BACKUP_OK.txt` (seed)
- [x] **Gate:** Phase 0 recorded. **Do not** `kind delete` until you confirm Phase C (cluster is already empty of stores)

### Test (grown)

- [ ] *(Phase 0 only)*

---

## Phase C — Clean four hosts

### Implement

- [x] Prereq: **Phase P + Phase 0** Tests green (SSH + Cloudflare MCP still up)
- [x] **Laptop only:** no `am-dev-*` clusters; leftover Kind `am-local` node + port-exposer removed. Docker engine kept. `~/.asrax` kept. blackbox/engage/resume left running
- [x] **Local only:** leftover Kind node containers removed
- [x] **VPS1:** `kind delete` `am-preprod`; removed `proxy-*` socat; image prune ~0.9 GB; `am-cloudflared` kept
- [x] **VPS2:** no Docker/Kind installed — already empty
- [x] **VPS3:** no Docker/Kind installed — already empty
- [x] Optional `/data/am-state` reset **skipped** — no tfstate on R2

### Test (this phase)

- [x] Kind empty: laptop (no kind nodes), VPS1 `No kind clusters found`, VPS2/VPS3 no kind
- [x] VPS disk: VPS1 20G/512G (was 24G); VPS2 938M/193G; VPS3 892M/435G
- [x] Laptop still has `~/.asrax` and `asrax-db-backups` `BACKUP_OK.txt`

### Test (grown)

- [x] Phase P: SSH VPS1/2/3 + Cloudflare MCP `asrax.in`
- [x] Phase 0 seed / R2 marker still on laptop

---

## Phase 1 — Terraform Kind module

### Implement

- [x] Prereq: Phase 0 gate; `am-infra-automation` checkout
- [x] Add `cluster_role` (infra | apps | platform | obs)
- [x] Add `api_server_port` (6443 / 6444 / 6445)
- [x] 1-node (`dev`/`dr`/`obs`) vs 2-node (`prod`) shape
- [x] Env tokens `dev` / `prod` / `dr` / `obs` only — hard-fail `local`, `preprod`, `hostbet-vps`
- [x] **Compute** Kind name: `am-<env>-<role>` except obs = `am-obs`. Do not accept free-form `cluster_name`
- [x] New stacks `terraform/kind-fleet/{dev,prod,dr,obs}/` only — do **not** apply `terraform/**/{local,preprod}`
- [x] Gitignore repo `*.tfstate`
- [x] Local backend path `~/.asrax/tfstate/dev/`; VPS backend `/data/am-state/terraform/{prod,dr,obs}/`
- [x] Fix leftover drawio text “destroy only am-local-*” → `am-dev-*`

### Test (this phase)

- [x] `terraform validate` / compile — all 10 kind-fleet stacks (`init -backend=false`)
- [x] Module can name a cluster without remote apply — `plan -refresh=false` `am-dev-infra` (no apply)
- [x] Planned names are `am-dev-*` / `am-prod-*` / `am-dr-*` / `am-obs` — **never** `am-preprod` or `am-local`
- [x] `env=local` and `env=preprod` fail validation (also `hostbet-vps`)

### Test (grown)

- [x] Phase 0 dump still on laptop
- [x] Hosts still clean until a track starts Phase 2 — no `kind create` / no `terraform apply`

Four tracks after this may run in parallel. Each track uses the **same Implement list** with its env token.

---

## Phase 2 — Infra + seed DBs (`am-*-infra`)

**Canonical order (every env — do not skip Edge):**

```text
kind create
  → Traefik + cloudflared + tunnel DNS (HTTPS → Traefik :80)
  → port-exposer + DNS-only A (TCP brokers only)
  → Helm stores + Vault
  → IngressRoutes (enable_gateway)
  → Test on domain (G27)
  → seed (only if Test green)
```

Prod and DR **must** run this same block (`terraform/kind-fleet/{prod,dr}/edge` then `stores`). A track that Helm-installs stores before Traefik is incomplete.

### Implement (before seed)

- [x] Prereq: Docker; `~/.asrax/credentials.env`; Phase 1
- [x] `kind create` `am-dev-infra` (or `am-prod-infra` / `am-dr-infra`) API **:6443** — laptop `am-dev-infra` only (2026-09-23). Prod/DR not created
- [x] kubeconfig `~/.asrax/kubeconfig.am-<env>-infra.yaml` — laptop `C:\Users\user\.asrax\kubeconfig.am-dev-infra.yaml` context `kind-am-dev-infra`
- [x] **Edge (gate):** Helm Traefik in `infra` via `modules/core/edge` — laptop retrofit applied 2026-09-23; prod/DR do this **before** any store Helm
- [x] **Edge (gate):** `cloudflared` + tunnel `asrax-<env>-tunnel` — origin **only** `http://traefik.infra.svc.cluster.local:80` (no per-Service bypass)
- [x] **Edge (gate):** proxied CNAME for HTTPS names (`vault`, `minio`, `s3`, `influx`, `traefik`, `pgadmin`, `mongo-express`, `kafka-ui`, `redis-ui`) → tunnel
- [x] Terraform/Helm: **PostgreSQL** in `infra`
- [x] Terraform/Helm: **MongoDB** in `infra`
- [x] Terraform/Helm: **Redis** in `infra`
- [x] Terraform/Helm: **Kafka** in `infra`
- [x] Terraform/Helm: **InfluxDB** in `infra`
- [x] Terraform/Helm: **MinIO** in `infra`
- [x] Terraform/Helm: **Vault** in `vault` — `injector.enabled=false`
- [x] Vault: enable KV `apps`; write policy `am-apps-read`
- [x] **Port exposer (every host incl. VPS):** `am-port-exposer` targets **`am-<env>-infra-control-plane` via Docker DNS** on network `kind` — **never** bake Kind bridge IP (`172.19.x`) into socat. After Docker restart the name still resolves; no Kind recreate. Dev: [terraform/kind-fleet/dev/exposer](../../terraform/kind-fleet/dev/exposer); prod/dr: same folder under `kind-fleet/{prod,dr}/exposer`
- [x] **Vault auto-unseal (every host incl. VPS):** Secret `vault-unseal-keys` from that host’s `vault-<env>-infra.json` (never git); stores Vault module `enable_watcher=true`, `enable_unsealer=false` → Deployment `vault-unsealer-watcher`. Day-2: no manual `vault operator unseal` after Docker/Kind restart
- [x] TCP DNS-only A for `postgres|mongo|redis|kafka-<env>.asrax.in` → host private IP (laptop `192.168.1.11`). Do **not** orange-cloud these
- [x] **Configure gateways:** `enable_gateway=true`; IngressRoutes for Vault / MinIO+S3 / Influx / Traefik dashboard / pgAdmin / mongo-express / kafka-ui / redis-ui. Host = prod bare / else `name-<env>.asrax.in`
- [x] Kafka `advertised.listeners` = `kafka-dev.asrax.in` (INTERNAL://kafka:9092 + EXTERNAL://kafka-dev.asrax.in:9092)
- [x] Create shared PG `platform` + Mongo `platform` (empty; before seed)
- [x] Create users/schemas on `platform`: `keycloak`, `temporal` (+ `temporal_visibility` schema), `lago`, `n8n`, `openproject`, `litellm`, `langfuse`; Mongo user `growthbook`
- [x] Vault listen / CSI addr = `https://vault-<env>.asrax.in` **via Traefik** (laptop retrofit; Service bypass removed)
- [x] MCP env file for this track: domain URLs only — `~/.asrax/credentials.d/dev.env`
- [ ] `am ai mcp-sync` pointed at Vault / Kafka / MinIO **by domain** — ran; deprecated sync kept only hub (`asrax`/`stitch`) and stripped host launchers from Cursor `mcp.json`. Restore Marketplace / `am ai sync` before next IDE reload. Domain tests used HTTP/python, not those MCPs
- [x] Install console **pods** (not public yet) — pgAdmin, mongo-express, kafka-ui, redis-commander

### Test (before seed) — domain only, no port-forward

- [x] Postgres connect + `SELECT 1` via `postgres-dev.asrax.in` (empty/new OK)
- [x] Mongo ping via `mongo-dev.asrax.in`
- [x] Redis `PING` via `redis-dev.asrax.in`
- [x] Kafka `list_topics` via `kafka-dev.asrax.in` (empty list OK)
- [x] Influx health via `https://influx-<env>.asrax.in/health` — through Traefik (not Service bypass)
- [x] MinIO / S3 live via `https://minio-<env>.asrax.in` or `https://s3-<env>.asrax.in/minio/health/live` — through Traefik
- [x] Vault status / write+read one KV via `https://vault-<env>.asrax.in` — through Traefik
- [x] `https://traefik-<env>.asrax.in` answers (dashboard or 200) — `/dashboard/` + `/api/version` 200
- [x] Tunnel ingress is Traefik + 404 catch-all only
- [x] Grep fail: `localhost` | `127.0.0.1` | `host.docker.internal` | `kubectl port-forward` used in this test
- [x] **Gate:** HTTPS HTTP-stores green **via Traefik**. TCP brokers stay DNS-only A (no `:443`). Seed still waiting for your go

### Implement (seed — only after Test before seed is green)

- [x] Restore `F:\am-repos\asrax-db-backups\postgres\*\latest` (`BACKUP_OK.txt`) — 17 DBs via `postgres-dev.asrax.in`
- [x] Restore `...\mongodb\*\latest` — ~202k docs; admin users reset after `--drop`; `growthbook` recreated on `platform`
- [x] Restore `...\redis\*\latest` — RDB loaded; **DBSIZE=0** (all keys already expired in dump TTL)
- [x] Restore `...\influx\*\latest` — kind dump via node tar; secret + Traefik `influxdb-token-injection` retargeted to restored operator token

### Test (after seed) — domain only, no port-forward

- [x] Shared PG/Mongo `platform` + per-module users still exist after seed (PG roles keycloak/n8n/…; Mongo `admin`+`growthbook`)
- [x] PG seed visible via `postgres-dev.asrax.in` (Keycloak `user_entity`=5)
- [x] Mongo seed visible via `mongo-dev.asrax.in` (portfolio=11012, market_data=172647)
- [x] Redis seed visible via `redis-dev.asrax.in` (PING ok; empty keyspace from dump TTL — not a restore failure)
- [x] Influx seed visible via `https://influx-dev.asrax.in` (buckets `_monitoring,_tasks,default`)
- [x] Vault / MinIO / Kafka still answer on the **same** domains (Vault/MinIO/S3 HTTPS 200; Kafka TCP `kafka-dev.asrax.in:9092`)
- [x] Still no port-forward; G26 grep still clean

### Test (grown)

- [x] Phase 0 dump still valid (`asrax-db-backups` used for seed)
- [x] `~/.asrax` not wiped by Phase C

---

## Phase 3a — Identity (`am-*-platform`)

**See also: [Phase ZT](#phase-zt--zero-trust--identity-admin)** (OTP enroll ZT-P0 after 3a/3e; role unify).

Resource allocation (CPU/mem tables for Keycloak/Argo/Temporal/Lago/P1 UIs/Novu): [`docs/kind-fleet-resources/SIZING.md`](../kind-fleet-resources/SIZING.md). Platform MCP / domain verify gate → **Phase 3e**.

### Implement

- [x] Prereq: Phase 2 Test + Test (grown) green
- [x] Create `terraform/modules/apps/keycloak` (Helm + realm; **drop Authentik**; image `bitnamilegacy/keycloak:26.3.3` / chart `25.2.0`)
- [x] Create `terraform/modules/apps/argocd` (Helm chart `10.8.0`; `prune: false`; HTTPS NodePort `30444`)
- [x] Wire both from `terraform/kind-fleet/<env>/platform` (+ `module.sizing` / `platform-sizing`)
- [x] `kind create` `am-dev-platform` (or prod/dr) API **:6445**
- [x] kubeconfig `~/.asrax/kubeconfig.am-<env>-platform.yaml`
- [x] Install **Keycloak**; realm `**am-realm`**
- [x] Roles: `am-admin`, `am-ops`, `am-viewer`, `am-user`
- [x] OIDC client `am-modern-ui` — redirect `https://am-<env>.asrax.in/...`
- [x] OIDC client `am-gateway`
- [x] OIDC client `minio`
- [x] OIDC client `grafana`
- [x] OIDC client `argocd`
- [x] OIDC client `headlamp`
- [x] OIDC client `kafka-ui`
- [x] OIDC client `pgadmin`
- [x] OIDC client `mongo-express`
- [x] OIDC client `redis-ui`
- [x] OIDC client `vault-ui`
- [x] OIDC client `influx-ui`
- [x] OIDC client `temporal-web`
- [x] OIDC client `lago`
- [x] OIDC client `n8n`
- [x] OIDC client `growthbook`
- [x] OIDC client `openproject`
- [x] OIDC client `litellm`
- [x] OIDC client `langfuse`
- [x] OIDC client `traefik`
- [x] OIDC client `novu` (redirect `https://novu-<env>.asrax.in/*`; **Helm deploy at 3d**)
- [x] All client secrets → Vault (not git). Redirects = `https://*.asrax.in` only
- [x] Test users `am-admin-test` (`am-admin`+`am-ops`) + `am-user-test` (`am-user`) → Vault write attempted `apps/data/<env>/infra/keycloak-test-users`
- [x] Install **Argo CD**; `prune: false`; enroll infra kube API (apps API in Phase 4)
- [x] Infra IngressRoutes + Endpoints bridge for `auth-<env>` / `argocd-<env>` (Traefik on infra; no second Traefik)
- [x] Cloudflare MCP + edge TF: `auth-<env>.asrax.in`, `argocd-<env>.asrax.in` → same tunnel as `vault-dev` (prod: `auth`, `argocd`)

### Test (this phase)

- [x] Keycloak Ready on platform (`bitnamilegacy/26.3.3`, DB `platform` / schema `keycloak`)
- [x] Keycloak MCP `search_users` on `https://auth-<env>.asrax.in` — found `am-admin-test` / `am-user-test` (**no port-forward**; overlay `credentials.d/keycloak-kind-fleet-dev.env`)
- [x] Argo MCP `argocd_status` + `list_applications` on `https://argocd-<env>.asrax.in` — **no port-forward** (overlay `credentials.d/argocd-dev.env`, `ARGOCD_MCP_PROFILE=dev`)
- [x] Every OIDC redirect is `https://*.asrax.in/...` (none `localhost` / `http://`)
- [x] In-cluster Host smoke: Traefik `Host(auth-dev.asrax.in)` + `Host(argocd-dev.asrax.in)` → bridges
- [x] Public domain smoke: `https://auth-dev.asrax.in` (OIDC well-known 200) + `https://argocd-dev.asrax.in` (200) — no port-forward
- [x] **Admin OIDC:** `am-admin-test` password-grant against client `argocd` → token OK (public `auth-dev`)
- [x] **User OIDC:** `am-user-test` password-grant against client `argocd` → token OK (public `auth-dev`)
- [x] Vault MCP readable `apps/data/<env>/infra/keycloak-test-users` (`am-admin-test` / `am-user-test` keys; policy `am-dev-laptop` + `credentials.d/vault-dev.env`)
- [x] Cloudflare MCP: `auth-dev.asrax.in`, `argocd-dev.asrax.in` CNAME → `asrax-dev-tunnel` (edge TF state matched)

### Test (grown)

- [x] Phase 2 seed still loaded
- [x] Shared PG/Mongo `platform` + users still present
- [x] Vault / MinIO / Kafka still answer on store domains (`vault-dev` health 200; `minio-dev` 200; `kafka-dev` DNS)
- [ ] G26 grep still clean on Vault infra

---

## Phase 3b — Temporal (P0)

### Implement

- [x] Prereq: Phase 3a both Tests green; PG role `temporal` + DBs `temporal` / `temporal_visibility` (separate DBs required by Temporal schema versioning; `btree_gin` extension)
- [x] Ensure `modules/apps/temporal` has `gateway.tf` + host suffix (`temporal-<env>.asrax.in` / prod bare)
- [x] Call module from `kind-fleet/<env>/platform`
- [x] Helm `temporalio/temporal` `0.62.0` on **platform** (not infra, not apps)
- [x] Frontend `:7233`; UI temporal-web (NodePort `30823`)
- [x] Connect to infra PG by DNS-only `postgres-<env>.asrax.in` (not `*.svc` across clusters)
- [x] Infra IngressRoute bridge + Cloudflare MCP: `temporal-dev.asrax.in` (prod `temporal.asrax.in`)

### Test (this phase)

- [x] Temporal UI `https://temporal-dev.asrax.in` — **200**, no port-forward
- [x] OIDC client `temporal-web` present in Keycloak (realm from 3a); UI is open for now (oauth2-proxy later if required)

### Test (grown)

- [x] Phase 3a Keycloak + Argo still on domain (`auth-dev` OIDC well-known 200)
- [x] Phase 2 stores still on domain
- [x] All Temporal server pods Ready; schema job Completed
---

## Phase 3c — Lago billing (P0)

### Implement

- [x] Prereq: Phase 3a; dedicated PG DB `lago` (OWNER `lago`, CREATEDB for Helm `db:create`) — not schema-on-`platform`
- [x] Ensure `modules/apps/lago` has `gateway.tf` + host suffix
- [x] Call module from `kind-fleet/<env>/platform` (NS `billing`)
- [x] Lago API + Lago front on **platform**
- [x] Postgres via `postgres-<env>.asrax.in` DB `lago`
- [x] Infra IngressRoute bridge + Cloudflare MCP: `lago-<env>.asrax.in` (prod `lago.asrax.in`)
- [x] **Do not** deploy `am-subscription`

### Test (this phase)

- [x] Lago UI `https://lago-<env>.asrax.in` — **no port-forward**
- [x] OIDC client `lago` (Keycloak realm client from Phase 3a)

### Test (grown)

- [x] Phase 3a + 3b still on domain
- [x] Phase 2 stores still on domain

---

## Phase 3d — P1 platform UIs

Implement only. Domain / MCP / OIDC verify for these hosts is **Phase 3e** (replay on prod/DR after apply).

### Implement

- [x] Ensure `modules/apps/{n8n,growthbook,openproject,litellm,langfuse,novu}` each have `gateway.tf` + host suffix
- [x] Call each module from `kind-fleet/<env>/platform` with `module.sizing.*` resources
- [x] n8n: attach user `n8n` to PG `platform` via `postgres-<env>.asrax.in`; CF `n8n-<env>.asrax.in`
- [x] GrowthBook: attach user `growthbook` to Mongo `platform` via `mongo-<env>.asrax.in`; CF `growthbook-<env>.asrax.in`
- [x] OpenProject: attach user `openproject` to PG `platform`; CF `openproject-<env>.asrax.in`
- [x] LiteLLM: attach user `litellm` to PG `platform` (NS `am-ai`); CF `litellm-<env>.asrax.in`
- [x] Langfuse: attach user `langfuse` to PG `platform` + Redis ACL + MinIO; ClickHouse in-module; CF `langfuse-<env>.asrax.in`
- [x] **Novu:** create `modules/apps/novu` from am-platform Helm (api/worker/web/ws); NS `notification`; Mongo DB `novu` + Redis `/2`; CF `novu-<env>.asrax.in`; sizing from `platform-sizing` (OIDC client already created in **3a**)
- [x] Infra IngressRoute bridge for each published host (existing Traefik + tunnel)

---

## Phase 3 — Ops lessons (laptop → VPS prod/DR)

Capture from laptop `dev` Phase 3a–3d so VPS1 (`prod`) / VPS3 (`dr`) replay is faster and does not repeat the same failures. Sizing stays env-specific ([SIZING.md](../kind-fleet-resources/SIZING.md)); never apply laptop prod sizes on Kind.

### Faster setup (do these first on every host)

1. **Edge before stores** — Traefik + cloudflared + tunnel, then DNS-only A for store ports (G26/G27). Never `localhost` / Docker bridge IPs in Vault, Helm, OIDC, or MCP.
2. **Preload images** — `modules/core/kind-image-preload` (or `crictl pull` on the Kind node) before Helm for GrowthBook / Langfuse / n8n / Lago / LiteLLM. Host `docker pull` alone is not enough.
3. **GrowthBook pin** — chart + image **`4.4.0`** (same as [am-infra `values-lab.yaml`](../../../am-infra/k8s/growthbook/values-lab.yaml)). Do **not** use `5.1.0` on Kind: containerd can serve a 0-byte `package.json` → `ERR_INVALID_PACKAGE_CONFIG`. Chart 4.4 uses pm2; leave default command.
4. **Lago** — dedicated PG database `lago` with OWNER + `CREATEDB` for Helm `db:create`. Not a schema on shared `platform`.
5. **OpenProject** — enable `btree_gist` + `pg_trgm`; JDBC/URL `search_path` must include `public` (`schema%2Cpublic`).
6. **Langfuse `DATABASE_URL`** — use `?schema=langfuse&sslmode=disable`. Prisma ignores `options=-csearch_path=…` and will fight `_prisma_migrations` in the wrong schema.
7. **Langfuse replicas / migrate** — **one** web replica. After first successful PG migrate, set `LANGFUSE_AUTO_POSTGRES_MIGRATION_DISABLED=true`. On **single-node** ClickHouse (no ZooKeeper), set `LANGFUSE_AUTO_CLICKHOUSE_MIGRATION_DISABLED=true` — auto migrate runs `ON CLUSTER` / ReplicatedMergeTree and CrashLoops.
8. **Vault** — keep init JSON at `~/.asrax/vault-<env>-infra.json` (VPS: `/data/am-state/...` equivalent). Create Secret `vault-unseal-keys` (`keys.json`). Set **`enable_watcher=true`**, **`enable_unsealer=false`**. Watcher pod auto-unseals after Docker/Kind restart. Liveness `sealedok=true` so a sealed pod is not killed before unseal.
9. **Port exposer** — socat targets Docker DNS name **`am-<env>-infra-control-plane`** on network `kind` (not a baked `172.19.0.x`). IP drift after Docker restart must not require terraform or Kind recreate. If broken: recreate **only** `am-port-exposer` container; then restart CrashLoop platform pods.

### Challenges faced (laptop Phase 3)

| Symptom | Root cause | Fix |
|---------|------------|-----|
| `vault-0` CrashLoop / sealed | File storage reseals; missing unseal secret; liveness 503; **watcher off** | Seed `vault-unseal-keys`; `enable_watcher=true`; sealedok probe; one-time unseal if needed |
| All apps: PG SSL EOF / P1001 | Exposer baked old Kind IP | Exposer must use Docker DNS hostname; recreate `am-port-exposer` only; restart platform pods |
| GrowthBook CrashLoop `ERR_INVALID_PACKAGE_CONFIG` | Image `5.1.0` layers empty `package.json` on Kind | Helm pin `4.4.0` chart+tag |
| Langfuse-web P3009 / two pods CrashLoop | Concurrent prisma migrate; failed row left open | Scale web to 1; mark failed migrations finished if objects exist; disable auto PG migrate |
| Langfuse-web CH migrate fail | `ON CLUSTER` needs ZooKeeper | Disable auto ClickHouse migrate on single-node CH |
| LiteLLM exit 137 | Default memory too low | Request/limit ≥2Gi |
| Lago workers Pending / starve | Chart default ~1100m CPU | Lower worker requests (e.g. 50m) on Kind |
| n8n CreateContainerConfigError / CrashLoop | Wrong image host, missing `N8N_HOST`, Redis DB clash | `n8nio/n8n` pin; set host; dedicated Redis DB index |

### Conclusions for prod/DR VPS

1. Replay the same `kind-fleet/<env>/` TF folders with the env token; **Phase 3e** is the reusable MCP/domain gate after 3a–3d.
2. After any Docker/Kind restart on that host (laptop **or VPS**): confirm exposer uses Docker DNS (recreate container only if needed) → **watcher auto-unseals Vault** → wait stores Ready → restart remaining CrashLoop platform pods. Do not chase app logs first. Do **not** `kind delete`.
3. Keep GrowthBook at **4.4.0** until that host’s containerd is proven clean with a newer tag.
4. Ship Langfuse with auto ClickHouse migrate **off** on single-node CH; apply CH DDL with a non-cluster path later if `traces` tables are missing.
5. Document every pin (chart versions, DB shape, migrate flags) in TF defaults — do not rely on live `kubectl set env` alone.
6. Never laptop prod sizes on Kind; VPS1/VPS3 use their own sizing rows.
7. **New VPS stand-up must ship** Docker-DNS exposer + `vault-unseal-keys` + `enable_watcher=true` on first stores apply — same as laptop. Copying `dev/stores` without these flags reintroduces sealed Vault and SSL EOF after the first Docker restart.

---

## Phase 3e — Platform MCP verify (`dev` | `prod` | `dr`)

Single reusable **Test** checklist after platform pieces (3a–3d). No new Helm here. Tokenize `<env>` / domains (`auth-dev` vs prod bare `auth`). Replay the same rows on VPS1 (`prod`) / VPS3 (`dr`) after platform apply — **never** laptop prod sizes.

Ops lessons: [Phase 3 — Ops lessons (laptop → VPS prod/DR)](#phase-3--ops-lessons-laptop--vps-proddr).

### Prep (every env)

- [x] `am ai sync` + `am ai mcp-sync --ide cursor --host-launchers` + reload Cursor *(Cloudflare restored; Keycloak/Argo fleet overlays written — reload MCP processes to pick up)*
- [x] `am creds doctor` — domain URLs in `credentials.d/dev.env` (`KEYCLOAK_URL`, `ARGOCD_URL`) + fleet overlays
- [x] Cloudflare MCP: zone `asrax.in` + tunnel `asrax-dev-tunnel` **healthy**

### Identity / GitOps

- [x] Keycloak MCP `search_users` on `https://auth-dev.asrax.in` — found `am-admin-test` / `am-user-test`
- [x] Argo MCP `argocd_status` + `list_applications` on `https://argocd-dev.asrax.in` (profile `dev`, 0 apps)
- [x] Admin + user OIDC password-grant on auth (`argocd` client) → Bearer OK

### Stores still up (grown)

- [x] Vault MCP read `apps/data/dev/infra/keycloak-test-users` OK; MinIO / Kafka domain HTTPS/TCP still answer (`minio-dev` 200; `kafka-dev` DNS)

### When 3b–3d deployed

- [x] Temporal MCP on `temporal-<env>.asrax.in` (prod: `temporal.asrax.in`) — **UI** `https://temporal-dev.asrax.in` **200**; Temporal MCP gRPC (`TEMPORAL_ADDRESS=temporal-dev.asrax.in:7233`) returns CF **530** (tunnel is HTTP origin only — expected until Temporal frontend TCP is published)
- [x] Lago / n8n / GrowthBook / OpenProject / LiteLLM / Langfuse / Novu: each domain HTTPS 200 or login redirect — **dev** verified 200/302 (OpenProject `/login`); restored missing `growthbook-platform` / `langfuse-platform` bridges (NodePort + IngressRoute). Admin/user SSO matrix deferred to oauth2-proxy wiring in Phase 4
- [x] Cloudflare MCP: every G24 platform host CNAME present for this env — all `*-dev.asrax.in` platform hosts resolve via CF-proxied DNS (edge `https_names`); Cloudflare MCP `execute` hook-blocked this session, DNS verified via public resolver

### amctl

- [x] `am ai status` clean for this env (credentials + IDE matrix OK)
- [x] Document: same Phase 3e rows on VPS1 (`prod`) / VPS3 (`dr`) after platform apply — never laptop prod sizes *(see [Phase 3 — Ops lessons](#phase-3--ops-lessons-laptop--vps-proddr))*

---

## Phase 4 — Apps Vault + am-gitops waves (4a–4g)

**Apps deployment model (two phases — do not mix):**

| Phase | What | How | Source of truth |
| --- | --- | --- | --- |
| **A — Vault** | All `apps/data/<env>/infra/*` + `services/*` + G25 CSI auth | **`terraform apply` only** (`vault-apps` seed + `module.vault_csi_auth` / `setup-g25-vault-auth.ps1`) | `kind-fleet/dev/vault-apps` + `apps-vault-seed` catalog — **not** Argo |
| **B — Workloads** | All product + agent pods | **Argo sync** Applications; default **`targetRevision: main`** (chart + values + image-tags) | `am-gitops` `main` — **not** hand `kubectl` / `am deploy` |

Order: **4a** Phase A (Vault/G25 terraform once) → **4b** gitops retarget + `dr/` scaffold → **4c–4f** Argo sync waves from **main** → **4g** Argo sync **all remaining** services from **main** + Postman closout. Do not skip gates. Helm/`am deploy` = break-glass only.

**Ops note (laptop → VPS prod/DR):** while running Phase 4 on laptop `dev`, keep short notes here (and in PLAN) of the one-time setup steps that make the next VPS prod/DR replay faster (CSI chart pin, `auth/kubernetes-apps`, Traefik bridge, Keycloak client, Vault path seeds, GHCR pull, CF DNS-only A for store hosts).

**Image roll (dev / prod / dr) — Argo sync from main:**
1. Never `tag: latest`. Look up the GitHub Actions **`main`** (analysis: **`master`**) workflow run / container id on GHCR.
2. **One service = one commit** updating `am-gitops/<env>/image-tags/<service>.yaml` (same pin in `dev` + `prod` + `dr` when promoting that build).
3. Merge that commit to **`am-gitops` `main`**.
4. Argo Applications stay **manual sync** (no `syncPolicy.automated`). After merge, **manually sync** the Application for the env you want (fleet `dev` first; user syncs `prod` / `dr` when ready). Default Application `targetRevision` for chart / values / imageValues = **`main`**.
5. Do not auto-roll all envs from one merge — sync is the promotion gate.

**targetRevision restriction (enforced):** `am-gitops/policies/target-revision.yaml` + `scripts/check-target-revision-policy.ps1` (CI). **Default for fleet apps deploy = `main`.** **prod** = `main`/`master` only (no feature branches). **dr** values = `main`/`master`/`dr`/`devstrategy`. **dev** may use a feature branch on values only when explicitly needed (dev strategy); chart + imageValues stay `main`/`master` everywhere.

**Domains only (G27) — no port-forward:** never `kubectl port-forward` for Phase 4 tests or debugging gates. Vault `apps/data/<env>/infra/*` and service secrets must use **actual** `*.asrax.in` hosts (stores + Vault + auth + `am-<env>`), never `localhost`, `127.0.0.1`, NodePort, or in-cluster `*.svc` from the apps cluster when stores live on infra. Smoke health/quote/login only via `https://am-<env>.asrax.in/...` and store domains.

### 4a — Apps cluster + Vault rewrite + G25

**Phase A — Vault sync (one shot — ready all services):** **`terraform apply` only** — not hand-seeding per wave, not Argo. After G25 CSI/auth is up, apply once so every catalog service has `apps/data/<env>/infra/*` + `apps/data/<env>/services/<svc>` (domains rewritten, fleet placeholders for third-party). Then Phase B (4c–4g) can Argo-sync any app without another Vault write.

```powershell
cd terraform/kind-fleet
.\init-backend.ps1 -Env dev -Role vault-apps
# Vault KV seed (apps-vault-seed):
.\dev\apps\scripts\seed-vault-dev-apps.ps1
# G25 CSI auth + SA bind (terraform target module.vault_csi_auth):
.\dev\apps\scripts\setup-g25-vault-auth.ps1 -Env dev
```

Stack: [`terraform/kind-fleet/dev/vault-apps`](../../terraform/kind-fleet/dev/vault-apps) · module [`apps-vault-seed`](../../terraform/modules/core/apps-vault-seed) · catalog [`catalog/services.yaml`](../../terraform/modules/core/apps-vault-seed/catalog/services.yaml) · G25 [`dev/apps` + `apps-vault-csi-auth`](../../terraform/kind-fleet/dev/apps). **Not** in am-gitops. Re-apply when the catalog grows; replace `*-fleet-*` placeholders in Vault when real secrets are needed.

**Fresh laptop wipe+redeploy (one shot):** [`dev/apps/scripts/fresh-redeploy-dev.ps1`](../../terraform/kind-fleet/dev/apps/scripts/fresh-redeploy-dev.ps1) / [`fresh-redeploy.ps1`](../../terraform/kind-fleet/dev/apps/scripts/fresh-redeploy.ps1):

1. **Phase A:** Vault backup/wipe (optional) → **`terraform apply` vault-apps seed** → **G25 terraform apply**
2. **Phase B:** pin GHCR tags (optional) → apply Application YAMLs → **Argo sync W1→W4** (each Application **`targetRevision: main` by default**) → domain smoke

Resume flags: `-SkipBackup -SkipWipe -SkipTerraform -SkipPin` / `-StartFromWave W2|W3|W4` / `-BatchSize N`.

**Codified fleet fixes (no manual kubectl/vault after seed):**
- Vault catalog: `TRIAL_GRANT_DELAY_HOURS` / `REFERRAL_*` numerics, `KAFKA_ENABLED=false` (subscription + notification + oms), full `am-agents` ops keys + `SUPPORT_AGENT_GATEWAY_PORT=8080`, `am-market-data.URL`, **`am-news`**, **`am-user-platform`**, **`am-oms`**, **`am-qa-agents`** (+ `runtime/modules/qa`), **`am-asrax-corp`**, **`am-mkt-agents`**, **`am-resume`**, identity `AM_MCP_*`
- GitOps `dev/apps`: **`am-oms`**, **`am-news`**, **`am-user-platform`**, **`am-asrax-corp`**, … (+ image-tags); **`am-asrax-ui`** + agents UIs live under `dev/agents` / `prod/agents`
- **n8n** Argo Application under `{env}/agents/n8n.yaml` (destination platform NS `n8n`); platform TF still seeds `n8n-secrets` + NodePort/route
- `setup-g25-vault-auth.ps1`: `ghcr-creds` alias + `am-apps-read` covers `apps/` and legacy `secret/data/dev/*`
- stores `db_users`: `am_subscription_user`, `am_user_platform_user` + dedicated DB ownership after restore
- GitOps / helm: support-agent port 8080 + worker replicas 0; email `KAFKA_REQUIRED=false`; pin script never writes `tag:"""`; corp/asrax-ui/mkt-portal `values.dev.yaml`; qa vault paths → `apps/data/dev/...`
- Redeploy waves: **W3** mid surface (corp/asrax-ui/mkt-portal + subscription/notification/logging/…); **W4** all agents (support/tool/db/qa/mkt/mcp)
- `minio-dev.asrax.in` DNS-only A → laptop LAN (was CF-proxied; hung corp `/health`); mkt Apps track `feature/youtube-mkt-dashboard` (no `main`)
- **Manual→codified (do not kubectl-hand-fix on next VPS):** `am-backend-sa` imagePullSecrets in apps/namespaces TF; Traefik `dev-global-cors`/`dev-strip-prefix` in `kind-fleet/dev/apps/middlewares.tf`; exposer `:80/:443`→apps Traefik; `ensure-argocd-repos.ps1` in fresh-redeploy; am-apps-read covers `runtime/*`; QA ingress **no strip /qa** (portal `https://am-dev.asrax.in/qa/ui`); `am-dev` must be DNS-only A to LAN (not CF tunnel) for Kind fleet

#### Implement

- [x] Prereq: Phase 3e green; Phase 2 DBs seeded
- [x] `kind create` `am-dev-apps` (or prod/dr) API **:6444** *(laptop `am-dev-apps` only; prod/DR deferred)*
- [x] NS `am-apps-<env>` + `edge` only
- [x] kubeconfig `~/.asrax/kubeconfig.am-<env>-apps.yaml`
- [x] Vault MCP: **read key names** from `apps/data/preprod/infra/postgres|mongodb|redis|kafka|influxdb|observability` *(via `vault-kind-nonprod` MCP — Contabo `vault.asrax.in` 530)*
- [x] **Terraform Vault sync (one go):** `terraform apply` in `kind-fleet/dev/vault-apps` — writes **all** `apps/data/<env>/infra/*` + **all** catalog `services/*` with `*.asrax.in` hosts (G23); wrapper `scripts/seed-vault-dev-apps.ps1` *(dev applied; 6 infra + 26 services)*
- [x] Catalog covers every Phase 4 service path up front (`am-identity`, `am-gateway`, `am-market-data`, `am-portfolio`, `am-trade-management`, agents, …) — no per-wave re-seed *(`catalog/services.yaml`)*
- [x] Mapping files stay in each chart’s `helm/vault-mappings.yaml` (no rewrite of key names)
- [x] On **apps** cluster: install secrets-store-csi-driver + vault-csi-provider DaemonSet *(CSI chart **1.4.8** — latest needs K8s ≥1.30; Kind is 1.27)*
- [x] Create SA `am-backend-sa` in `am-apps-<env>`; `automountServiceAccountToken: true`
- [x] Attach `regcred` + `github-registry-secret` to `am-backend-sa`
- [x] Create SA `vault-auth-reviewer` in apps `kube-system` + `system:auth-delegator`
- [x] On infra Vault: `vault auth enable -path=kubernetes-apps kubernetes` (fleet apps API; preprod VPS uses `auth/kubernetes` — match overlay `authPath` to this mount)
- [x] `vault write auth/kubernetes-apps/config` `kubernetes_host=https://<apps-node-ip>:6443` + reviewer JWT + CA *(from vault pod use Kind node IP :6443, not host :6444)*
- [x] `vault write auth/kubernetes-apps/role/am-backend-role` bound to `am-backend-sa` / `am-apps-<env>` / policy `am-apps-read`
- [x] Confirm Vault Helm **injector.enabled=false**; pods will use `https://vault-<env>.asrax.in`
- [x] Remaining G24 hosts on the **existing** Phase 2 Traefik + tunnel (do **not** Helm-install Traefik again)
- [x] Wire OIDC or oauth2-proxy for each G24 UI → `am-realm` *(platform G24 done in 3e; app hosts bridged in 4c+)*

#### Test

- [x] CSI Job / SA can login to Vault role `am-backend-role` *(pod `vault-csi-login-test` → `LOGIN_AND_READ_OK`)*
- [x] Grep fail: `localhost` | `127.0.0.1` | `host.docker.internal` | `*-preprod.asrax.in` | Contabo TCP
- [x] Vault list: `apps/data/<env>/infra/*` + every catalog `services/*` present after terraform apply *(dev: 26 services)*
- [x] **Gate:** cluster can read Vault; secrets ready for **all** Phase 4 apps in one go; **no** product pods required yet

### 4b — Argo + am-gitops (`dev` retarget + `dr` scaffold)

#### Implement

- [x] In [am-gitops](../../../am-gitops): add `dev/values-overlays/vault-https-dev-fleet.yaml` modeled on [vault-https-preprod.yaml](../../../am-gitops/preprod/values-overlays/vault-https-preprod.yaml) — `address: https://vault-dev.asrax.in`, `authPath` matching 4a mount, `role: am-backend-role`, CSI on *(Applications also inline the same until overlay is on `main`)*
- [x] Stop using `vault-https-asrax.yaml` / JWT-to-`vault.asrax.in` for laptop fleet Applications
- [x] Register Kind apps cluster in Argo; set Application `destination` to that cluster / NS `am-apps-dev` (not Contabo `am-vps-nonprod` for fleet work) *(secret `cluster-am-dev-apps` → Docker IP:6443)*
- [x] Keep `prune: false`; do **not** sync all apps at once *(automated sync removed; root auto off)*
- [x] **`dr/` missing → create:** copy `preprod/` → `dr/apps`, `image-tags`, `values-overlays`, `dr-apps-root.yaml`; overlay `vault-https-dr.yaml` (`https://vault-dr.asrax.in`); hosts `*-dr.asrax.in`; leave unsynced until Phase 6 — **fleet tree now on disk** via `scripts/scaffold-fleet-env.ps1` from `dev/` (`dr/` + retargeted `prod/` + aligned `preprod/agents`)

#### Test

- [x] Argo MCP lists `dev-apps-root` + expected apps; dry-run sync one chart *(manifests generate: Service/Deployment/SPC for `am-gateway-dev` → OutOfSync/Missing; no pods)*
- [x] `dr-apps-root` Application exists on cluster (Synced/Unknown OK if DR cluster not up)
- [x] **Gate:** gitops can deploy into laptop `am-apps-dev`; `dr/` tree present *(push `am-gitops` when ready so file-based overlay is on `main`)*

### 4c — Gateway (API + AI) + modern-ui

#### Implement

- [x] Sync from [dev/apps](../../../am-gitops/dev/apps): `am-gateway`, `am-api-gateway` / `am-asrax-proxy` as needed, `am-ai-gateway`, `am-modern-ui` — CSI + `am-backend-sa`
- [x] Bridge `am-<env>.asrax.in` on existing Phase 2 Traefik (no new Traefik Helm) *(apps-cluster Traefik NodePort + infra `am-apps-edge` IngressRoute + CF tunnel hostname)*

#### Test

- [x] Domain HTTPS 200 or Keycloak challenge; gateway health *(`/` 200 UI; `/gateway` 401 without token)*
- [x] Each G24 host still 200 / challenge (grown from Phase 3) *(auth-dev 302; argocd-dev 200; vault-dev health 200)*

### 4d — Identity + login/token Test (hard gate)

#### Implement

- [x] Sync `am-identity` (+ `am-subscription` / `am-notification` only if required for login)
- [x] Vault CSI + isolation grep

#### Test

- [x] `am-admin-test` / `am-user-test` login via gateway → `access_token`
- [x] One protected call **200** *(Bearer → `GET /identity/users/me/security-events` 200; no-auth 401. Note: `GET /users/me` 500 — missing `is_user_deletion_pending` on Keycloak provider in current image)*
- [x] **Gate:** do **not** start 4e until green

### 4e — Market data

#### Implement

- [x] Pin image from GitHub **`main`** workflow container id (not `latest`) in `dev/image-tags/am-market-data.yaml` *(tag `35459440042`)*
- [x] Sync `am-market-data`; CSI + `am-backend-sa`

#### Test

- [x] Health + one quote on `https://am-<env>.asrax.in/market` (prod: `am.asrax.in/market`) — **domain only, no port-forward** *(`/actuator/health/liveness` 200; `/v1/market-data/quotes?symbols=RELIANCE` 200 — empty-price OK with placeholder Upstox; readiness may be DOWN until store deps green)*
- [x] Pod: SA `am-backend-sa`; CSI volume; **zero** Vault sidecar containers
- [x] Vault mongo/redis/influx/kafka hosts are `*-<env>.asrax.in` (not Contabo IP, not `localhost`) *(fixed CF A: `mongodb-dev`/`influxdb-dev` → laptop LAN; Vault influx `http://influxdb-dev.asrax.in:8086`)*

### 4f — Portfolio / trade / doc / news

#### Implement

- [x] One-at-a-time: `am-portfolio` → `am-trade-management-service` → `am-document-processor` → news/analysis app *(pins: portfolio `35856161500`, trade `31089449283`, doc `34125590336`, analysis `33862449638` — also written to `prod/` + `dr/` image-tags)*
- [x] Isolation grep after each *(SA `am-backend-sa`; CSI; no Vault sidecar)*

#### Test

- [x] Each app Ready + CSI; spot health only (full API matrix in 4g) *(`https://am-dev.asrax.in/{portfolio,trade,doc/processor,analysis}/actuator/health` 200)*
- [x] Phase 2 stores + Phase 3 Keycloak/Argo still up

### 4g — Remaining services (Argo from main) + Postman MCP final gate

**Phase B remaining:** after Vault is already on terraform (4a), sync **all remaining** apps + agents via **Argo from `am-gitops` `main`** (default `targetRevision: main`). Do **not** re-seed Vault per service. Prefer `fresh-redeploy.ps1 -SkipTerraform -StartFromWave W3|W4` or Argo MCP / UI sync of each Application.

#### Implement

- [x] Confirm Phase A already applied (`vault-apps` + G25); skip terraform unless catalog/G25 changed *(re-applied vault-apps seed 2026-09-24; G25 no-op)*
- [x] Argo sync remaining [dev/apps](../../../am-gitops/dev/apps) + [dev/agents](../../../am-gitops/dev/agents) (+ `dev/apps-full` as needed) not green in 4c–4f — **from `main`**: W1–W4 wave sync after server-side apply of Application YAMLs *(laptop Ready; live Application specs include kafka `:9092` + Temporal rpc — push to `am-gitops` `main` still needed so git matches cluster)*
- [x] Application YAML: chart / values / imageValues `targetRevision: main` by default (dev feature branch only when explicitly needed)
- [x] Add missing Application YAML under `dev/apps` or `dev/agents` (and `dr/` mirror) before sync if a known AM service has none *(oms/news/user-platform/corp/asrax-ui + agents tree on main `db2298e`)*
- [x] Merge fleet overlays (`fleet-common`, kafka `:9092`, Temporal HTTPS UI + `temporal-rpc` gRPC, agents NS) to **`am-gitops` `main`** so cluster Applications match git *(pushed `db2298e` 2026-09-24)*

#### Test (Phase 4 closout)

- [x] Every synced app Ready; CSI present; **zero** Vault sidecars *(2026-09-24: `am-apps-dev` 21/21 Ready + CSI vols; `am-agents-dev` 10/10 Ready; no vault-agent sidecars)*
- [x] Postman MCP: resolve shared **dev** env (`AM — Dev`); `base_url` / service URLs → `https://am-dev.asrax.in/{identity,market,portfolio,…}`; `keycloak_url` → `https://auth-dev.asrax.in` (no `/auth`); `keycloak_realm` → `am-realm`; `identity_client_id` → `am-identity-service`; test user `am-admin-test@asrax.in` from Vault `apps/dev/infra/keycloak-test-users`
- [x] Postman MCP: `getCollections` (Asrax workspace) listed; **`runCollection` from Postman Cloud cannot reach fleet** — `am-dev.asrax.in` is DNS A → LAN `192.168.1.11` (by design). Closout API verify done **from laptop** (curl / local Postman) against same env vars.
- [x] Core happy-path green from laptop (2026-09-24): OIDC password-grant `am-admin-test` OK; health UP for identity/market/portfolio/trade/analysis/doc/parser; `GET /portfolio/v1/portfolios` → **200 `[]`** (auth OK, empty data — not 401/5xx). Traefik `dev-strip-prefix` was missing app prefixes (`/market`,`/portfolio`,…) — fixed in `kind-fleet/dev/apps/middlewares.tf` + live Middleware (+ `parser-strip-prefix`).
- [x] Grep fail: no `host.docker.internal` / plain `http://vault` in `am-gitops/dev`. Remaining: CORS allowlist `localhost:9000` in `am-ai-gateway` overlay (Flutter local); Contabo IP only in unused `hostaliases-contabo-tcp.yaml` (README: do not attach); `argocd-preprod` mention in README only.
- [x] `am-admin-test` / `am-user-test` present in Keycloak `am-realm`; passwords restored to Vault `apps/dev/infra/keycloak-test-users`
- [x] **Gate:** Phase 4 complete for Kind-fleet laptop — apps/agents Ready from **main**; Vault seed + G25 CSI; strip-prefix routing fixed; Postman **AM — Dev** env corrected; core auth+health+portfolio list verified on LAN. Re-run full `runCollection` from **desktop Postman** (not Cloud) when needed.

### 4h — Fleet Grafana + Loki (bare FQDN hub)

**Scope:** `https://grafana.asrax.in` + `loki` / `prometheus`.asrax.in on Kind-fleet (interim hub until Phase 11 VPS2). Dashboards via **am-obs-platform** HTTP API (ADR-010) — not gitops ConfigMaps. GitOps am-logging `LOKI_URL` → bare Loki.

#### Implement

- [x] Terraform `kind-fleet/dev/obs`: Grafana + Loki + Prometheus on `am-dev-platform`; Keycloak OIDC; NodePorts + cross-cluster bridges; state `~/.asrax/tfstate/dev/obs/` *(Grafana NodePort **30350** — 30300 owned by GrowthBook)*
- [x] Edge CF: `bare_https_names` grafana/loki/prometheus → no `-dev`; tunnel ingress Host(`*.asrax.in`)
- [x] Vault `apps/data/dev/infra/observability` (admin pw + bare URLs) when token present
- [x] Alloy DaemonSets: apps + infra → `https://loki.asrax.in` / `https://prometheus.asrax.in`; platform in-cluster gateway
- [x] am-obs `targets/dev-fleet` → `grafana.asrax.in`; publish catalog via `platform_ctl`
- [x] am-gitops `dev/apps/am-logging.yaml`: `LOKI_URL` → `https://loki.asrax.in/loki/api/v1/push`
- [x] Re-apply edge/obs/alloy + CF after bare-FQDN cutover; re-run Keycloak client redirect for `grafana`
- [x] Re-run `scripts/setup-grafana-dev-mcp.ps1` (creds URL → grafana.asrax.in)

#### Test (gate)

- [x] Login `https://grafana.asrax.in` via Keycloak *(redirect URIs updated; login page 200)*
- [x] Loki + Prometheus datasources OK; LogQL from apps/agents/infra NS *(MCP setup: 2 DS / 14 boards)*
- [x] am-obs-published boards visible
- [x] **Grafana MCP (fleet):** SA token; LogQL OK — [GRAFANA_FLEET_DEV.md](GRAFANA_FLEET_DEV.md)
- [x] Stale `*-dev` CNAMEs optional cleanup (not required for Host match)
### Test (grown) — after 4g

- [ ] Phase 2 DBs still seeded; store domains still answer
- [ ] Phase 3 Keycloak + Argo still on domain
- [ ] OIDC redirects still domain-only

---

## Phase 5 — VPS connect + security (before any VPS Kind)

**See also: [Phase ZT](#phase-zt--zero-trust--identity-admin)** (ZT-IP data-plane allowlist syncs with exposer / WG — do not rewrite 5.x bullets).

**Scope:** No Kind / terraform on a VPS until that host’s Test gate is green. Day-2 = **`am-ops` only**. Kind create/stop/delete = **G1** root break-glass only. Do **not** wipe Contabo until Phase 7.

**IPs:** [VPS/.env](../../../VPS/.env) — `VPS_IP` / `VPS_2_IP` / `VPS_3_IP` (never commit passwords).  
**Runbook:** [PHASE5_VPS_SECURITY.md](PHASE5_VPS_SECURITY.md). **Scripts:** [`scripts/vps-security/`](../../scripts/vps-security/).

**Loop:** Setup (scp + `install-phase51.sh` as root once) → Implement → `am ai sync` (+ Cloudflare MCP if needed) → Test (gate: shell + MCP) → Test (grown).

---

### 5.1 VPS1 Contabo (prod host)

#### Setup

- [x] Prereq: Phase P + Phase 0 Tests green; SSH key; `VPS_IP` reachable *(e.g. `203.174.22.129`)*
- [x] `scp scripts/vps-security/* am-vps1:/tmp/am-vps-security/`
- [x] Root **once:** `ssh am-vps1 'bash /tmp/am-vps-security/install-phase51.sh'`
- [x] Day-2 alias: reconnect as **`am-vps1-ops`** (`am-ops`, key-only)

#### Implement

- [x] User `am-ops`; key-only SSH; password login disabled for day-2
- [x] **No sudoers** for `am-ops`
- [x] Install `am-ops-guard` wrappers (`kubectl` / `kind` / `terraform` — blocks destroy/delete except G1)
- [x] Install `break-glass-kind.sh` allowlist: `kind create|delete`, `docker stop|start` Kind, `cloudflared`, `pg_ctl promote`, Mongo `rs.stepUp`
- [x] Log `/var/log/am-break-glass.log`
- [x] `/data/am-state` writable by `am-ops`; root kubeconfig `0400` root-only

#### Test (gate) — SSH + guard + MCP

**Shell** (see [PHASE5_VPS_SECURITY.md](PHASE5_VPS_SECURITY.md)):

- [x] Reconnect **only** as `am-ops` (`am-vps1-ops`)
- [x] `sudo true` fails
- [x] `kubectl delete` refused (`am-ops-guard`)
- [x] G1 script is the only Kind path; `/var/log/am-break-glass.log` exists

**MCP** (`user-cloudflare` — no Contabo / SSH / Vault MCP for this gate):

- [x] Cloudflare MCP: zone `asrax.in` listable
- [x] Cloudflare MCP: tunnels listable (incl. `asrax-prod-tunnel` as relevant)
- [x] Cloudflare MCP: R2 / `asrax-disaster` listable *(disaster-path sanity)*
- [x] **Gate:** 5.1 green before Phase 8 (Phases 6–7 may still use live Contabo)

#### Test (grown)

- [x] Phase 0 dump / R2 prefix still reachable from laptop

---

### 5.2 VPS2 obs / Grafana host

#### Setup

- [x] Prereq: VPS2 bought (`VPS_2_IP`); Phase P + Phase 0
- [x] `scp scripts/vps-security/* am-vps2:/tmp/am-vps-security/`
- [x] Root **once:** `ssh am-vps2 'bash /tmp/am-vps-security/install-phase51.sh'`
- [x] Day-2 alias: **`am-vps2-ops`**

#### Implement

- [x] Same as 5.1: `am-ops`, key-only, no sudo, `am-ops-guard`, G1 script, `/data/am-state`

#### Test (gate) — SSH + guard + MCP

**Shell:**

- [x] `am-ops` SSH (`am-vps2-ops`); `sudo true` denied
- [x] `kubectl delete` refused
- [x] G1 script + break-glass log present

**MCP** (`user-cloudflare`):

- [x] Zone `asrax.in` listable
- [x] Tunnels listable (obs / prod tunnels as relevant)
- [x] R2 `asrax-disaster` listable
- [x] **Gate:** required before **Phase 11** only (does not block wipe / Phase 6–8)

#### Test (grown)

- [x] 5.1 still green if Contabo still live *(optional recheck)*

---

### 5.3 VPS3 DR

#### Setup

- [x] Prereq: VPS3 bought (`VPS_3_IP`); **RAM ≥ 32 GB**; Phase P + Phase 0 *(MemTotal 31.34 GiB / Contabo 32 GB class — SI ≥ 32e9 B)*
- [x] `scp scripts/vps-security/* am-vps3:/tmp/am-vps-security/`
- [x] Root **once:** `ssh am-vps3 'bash /tmp/am-vps-security/install-phase51.sh'`
- [x] Day-2 alias: **`am-vps3-ops`**

#### Implement

- [x] Same as 5.1: `am-ops`, guard, G1 (include **promote / rs.stepUp**)
- [x] Install **WireGuard** VPS1↔VPS3 — `install-wireguard-vps1-vps3.sh` (`ROLE=vps1|vps3`, peer IP + pubkey) *(wg0 `10.77.1.1`↔`10.77.1.2`, UDP 51820)*
- [x] Allow only `:5432` and `:27017` on the WG interface *(iptables `AM-WG-STORES`)*
- [x] Do **not** publish PG/Mongo on the public NIC *(DROP on eth0/ens3; no listeners)*

#### Test (gate) — SSH + guard + WG + MCP

**Shell:**

- [x] VPS3 RAM ≥ 32 GB *(Contabo 32 GB SKU; MemTotal 32865092 KiB)*
- [x] `am-ops` SSH; `sudo true` fails; `kubectl delete` REFUSED
- [x] WG ping both ways (VPS1↔VPS3 / `10.77.1.1`↔`10.77.1.2`)
- [x] `:5432` / `:27017` not on public NIC

**MCP** (`user-cloudflare`):

- [x] Zone `asrax.in` listable
- [x] Tunnels listable
- [x] R2 `asrax-disaster` listable
- [x] **Gate:** required before **Phase 6**

#### Test (grown)

- [x] 5.1 still green if Contabo is still live *(BatchMode `kubectl delete` → am-ops-guard REFUSED; sudo denied)*

---

## Phase 6 — DR + replica (users still on VPS1)

### Implement

- [x] Prereq: Phase 5.3 WG green; VPS3 ≥ 32 GB; VPS1 still serving
- [x] G1: `kind create` `am-dr-infra` :6443 *(2026-09-24 break-glass; kubeconfig `/data/am-state/kubeconfig.am-dr-infra.yaml`)*
- [x] G1: `kind create` `am-dr-apps` :6444
- [x] G1: `kind create` `am-dr-platform` :6445
- [ ] Repeat **Phase 2 Implement** on DR — **Edge first** (Traefik + `asrax-dr-tunnel` + CNAME), then TCP A + **exposer (Docker DNS `am-dr-infra-control-plane`)**, then stores (`enable_watcher=true` + seed `vault-unseal-keys`), then IngressRoutes. Do not skip Edge; do not bake Kind IP; do not ship `enable_watcher=false` *(partial 2026-09-24: Edge Traefik+cloudflared+CNAMEs + `asrax-dr-tunnel` healthy + exposer `am-port-exposer` up; **stores still sizing stub**)*
- [ ] Seed DR/VPS1 from `asrax-db-backups` **as soon as DBs exist** (before AM apps)
- [ ] Repeat **Phase 3 Implement** on DR (Keycloak, all OIDC clients, Argo, Temporal)
- [ ] Repeat **Phase 4 Implement (4a–4g)** on DR: Vault keys → `apps/data/dr/…` (rewrite to `*-dr.asrax.in`) + G25 SA/CSI + am-gitops `dr/` waves through Postman MCP closout (or DR-equivalent API verify)
- [ ] G20: Postgres **standby** on VPS3 from VPS1 primary over WireGuard
- [ ] G20: Mongo **secondary** on VPS3 from VPS1 primary over WireGuard
- [ ] **No** R2 restore cron onto PG/Mongo
- [ ] Cloudflare MCP: `am-dr.asrax.in`, `auth-dr.asrax.in`, all G24 `*-dr.asrax.in`
- [ ] Cloudflare LB: VPS1 primary / VPS3 fallback on `am` + `auth`; health `/health`; **auto-failback off**
- [ ] Isolation: **no** `am-apps-prod` on VPS3

### Test (this phase)

- [ ] Replica lag seconds (PG + Mongo)
- [ ] Every G24 **DR** host on `*-dr.asrax.in`
- [ ] G19: `https://am-dr.asrax.in` shell + live quotes
- [ ] G15: prod JWT → DR gateway **200**
- [ ] No `am-apps-prod` on VPS3
- [ ] DR **not** taking prod writes
- [ ] G25: no Vault sidecar on DR AM pods (spot-check `am-market-data` + one 4g service)

### Test (grown)

- [ ] Local track (if run) still domain-only
- [ ] Phase 5.3 WG still up
- [ ] Phase 0 dump still on laptop
- [ ] Prod `/health` still via `https://am.asrax.in` if VPS1 still live

---

## Phase 7 — Promote VPS3; fence VPS1

### Implement

- [ ] User confirmed; replica lag OK; laptop daily R2 pull
- [ ] G1+G2: **stop VPS1 Kind** (or host dead)
- [ ] G20: `pg_ctl promote` on VPS3 (G1 allowlist)
- [ ] G20: Mongo `rs.stepUp` on VPS3
- [ ] Do **not** edit DNS; CF LB already failing over
- [ ] Do **not** restore R2 onto the live replica

### Test (this phase)

- [ ] CF LB serves VPS3 with **no** DNS click
- [ ] Still logged in (G15); quotes + positions live (G19 + G20)
- [ ] One writer on VPS3; VPS1 writers 0

### Test (grown)

- [ ] G24 hosts still domain-only (`am.asrax.in` now on DR)
- [ ] G26 grep still clean
- [ ] First AM wave set still matches Phase 4a–4g (not market-data-only)

---

## Phase 8 — Rebuild VPS1 (users stay on DR)

### Implement

- [ ] Prereq: Phase 7 + Phase 5.1; laptop pull still on disk; VPS2 (Grafana) **not** required
- [ ] G1: `kind delete` leftover on VPS1
- [ ] G1: `kind create` `am-prod-infra` / `am-prod-apps` / `am-prod-platform` (2-node)
- [ ] Repeat **Phase 2 Implement** on prod — **Edge first** (Traefik + `asrax-prod-tunnel` + CNAME), then TCP A + **exposer (Docker DNS `am-prod-infra-control-plane`)**, then stores (`enable_watcher=true` + seed `vault-unseal-keys`), then IngressRoutes. Do not skip Edge; do not bake Kind IP; do not ship `enable_watcher=false`
- [ ] Seed if DBs empty from `asrax-db-backups` (or attach as standby — do not R2-restore over a replica)
- [ ] Attach VPS1 Postgres as **standby** of VPS3 primary (WG)
- [ ] Attach VPS1 Mongo as **secondary** of VPS3 primary (WG)
- [ ] Repeat **Phase 3 Implement** (Keycloak, all OIDC clients, Argo, Temporal)
- [ ] Repeat **Phase 4 Implement (4a–4g)**: Vault `apps/data/prod/…` rewrite to prod domains + G25 + am-gitops `prod/` waves through Postman MCP closout
- [ ] **No Grafana** on VPS1. **No kagent**
- [ ] Isolation: no `am-apps-dev|dev|preprod` on VPS1

### Test (this phase)

- [ ] Prod MCP on prod **domains**
- [ ] Isolation grep: no local/dev/preprod app NS
- [ ] VPS1 replica catching up
- [ ] **Do not** unfence VPS1 yet

### Test (grown)

- [ ] Users still on DR / CF LB
- [ ] Still one writer (VPS3)
- [ ] G26 grep clean on rebuilt prod Vault
- [ ] G25: no sidecar on prod AM pods (spot-check `am-market-data` + one 4g service)

---

## Phase 9 — Failback to VPS1

### Implement

- [ ] Prereq: Phase 8; VPS1 replica caught up
- [ ] Human: make VPS1 PG+Mongo primary (or keep VPS3 writer and only flip LB — **one** writer)
- [ ] Set CF LB primary = VPS1; VPS3 back to standby
- [ ] Auto-failback stays **off**

### Test (this phase)

- [ ] `https://am.asrax.in` hits VPS1
- [ ] Still logged in

### Test (grown)

- [ ] All G24 prod hosts still work on domain
- [ ] Auto-failback still off
- [ ] G20: VPS3 is standby again

---

## Phase ZT — Zero-trust + Identity Admin

Pointers only — detail in [`../ZERO_TRUST_ACCESS.md`](../ZERO_TRUST_ACCESS.md) and [`am-platform/docs/features/enterprise-identity-admin-rbac.md`](../../../am-platform/docs/features/enterprise-identity-admin-rbac.md). Do **not** rename fleet Phase 0 (protect data). Zero-trust enroll = **ZT-P0**.

**Gates:** ZT-P0 after Phase 3a/3e · ZT-IP after Phase 2 exposer (+ Phase 5 on VPS) · ZT-EDGE with Phase 11 · ZT-P1 with / before Phase 10.

### Implement

- [x] **ZT-D0** Docs pack published (ZERO_TRUST_ACCESS + enterprise-identity-admin-rbac + features README)
- [ ] **ZT-P0** Keycloak OTP optional; ops enroll TOTP on `auth-dev`; Access still off (`access_enforce=false`)
- [ ] **ZT-R** Canonical roles `user`/`viewer`/`ops`/`admin`/`super_admin`/`service`; create/invite defaults `user` or `viewer`
- [ ] **ZT-UI** Identity Admin console (modern-ui) — users, roles help, groups, custom roles
- [ ] **ZT-IP** GitHub `register-access-ip.yml` → `access-allowlist/registry.json` → Access apps + data-plane firewall
- [ ] **ZT-EDGE** `modules/core/zero-trust-access` wired from `kind-fleet/dev/edge`; Alloy Service Token same apply as Loki/Prom Access
- [ ] **ZT-P1** `mfa_enforce=true` + `access_enforce=true`; human clients `directAccessGrantsEnabled=false`; Grafana/Argo local password off (see Phase 10)
- [ ] **ZT-V** Smoke: `user` deny Grafana; `viewer` read-only; password-grant → 401; unregistered IP refuse store TCP

### Test (this phase)

- [ ] `auth-dev.asrax.in` reachable with **no** Access cookie (Keycloak login)
- [ ] After ZT-P1: Grafana Access challenge without session; Alloy still pushes to Loki/Prom
- [ ] Create/invite from Identity Admin → realm roles `user` or `viewer` only on standard form

### Test (grown)

- [ ] Phase 3a Keycloak still on domain
- [ ] Phase 2 store domains still answer
- [ ] Phase 10 / 11 tests remain the SoT for SSO / obs — tick those after ZT-P1 / ZT-EDGE

---

## Phase 10 — SSO prove

**See also: [Phase ZT](#phase-zt--zero-trust--identity-admin)** (ZT-P1 MFA + Access enforce; tick these tests after ZT-P1).

### Implement

- [ ] Drop Authentik everywhere on new clusters
- [ ] Point Grafana OIDC → `https://auth.asrax.in/realms/am-realm`
- [ ] Point MinIO / Argo / Headlamp / remaining G24 → same realm
- [ ] Disable human Grafana password (break-glass password only in Vault)

### Test (this phase)

- [ ] `am-admin` opens **every** G24 console by domain (modern-ui, gateway, MinIO, Grafana, Keycloak, Argo, Headlamp, Kafka UI, pgAdmin, Mongo, Redis, Vault, Influx, Temporal, Traefik)
- [ ] `am-user` denied Grafana / MinIO / infra consoles
- [ ] No Authentik issuer; no localhost redirect

### Test (grown)

- [ ] Phase 4/6 AM apps (market quotes + identity token path) still live
- [ ] G26 grep still clean

---

## Phase 11 — VPS2 obs / Grafana (parallel)

**See also: [Phase ZT](#phase-zt--zero-trust--identity-admin)** (ZT-EDGE Alloy Service Token hard-coupled with Loki/Prom Access).

**Sizing / retention / FQDNs:** [OBS_VPS2_SIZING.md](OBS_VPS2_SIZING.md).  
**Ops/dev hub + credentials:** [VPS2_DEV_PLATFORM.md](VPS2_DEV_PLATFORM.md) — prefer **≥16 GB** if platform apps colocated.

### Implement (11 — obs)

- [ ] Prereq: Phase 5.2; Phase 0. Prefer **before Phase 7** if VPS2 exists (G9)
- [ ] Kind `am-obs` API :6443 on **VPS2**
- [ ] Install **Grafana** (resources/PVC per [OBS_VPS2_SIZING.md](OBS_VPS2_SIZING.md))
- [ ] Install **Prometheus** — retention **30d**, PVC ~40 Gi
- [ ] Install **Loki** — retention **14d**, caches off, PVC ~80 Gi
- [ ] Install **Tempo** — retention **5d**, PVC ~50 Gi
- [ ] **CronJob log-janitor** every 6h: if Loki PVC ≥ 80% (or always), clean logs older than retention
- [ ] Alloy on other hosts → VPS2 HTTPS push to bare FQDNs (`loki` / `prometheus` / `tempo`.asrax.in)
- [ ] State `/data/am-state/terraform/obs`
- [ ] **No** product `am-apps-*`, **no** kagent on VPS2
- [ ] Cloudflare MCP (**after** Test health), tunnel → VPS2 Traefik/edge:
  - [ ] `grafana.asrax.in`
  - [ ] `loki.asrax.in`
  - [ ] `prometheus.asrax.in`
  - [ ] `tempo.asrax.in`

### Implement (11b — platform + credentials hub)

- [ ] Install **Vault** on VPS2; seed **`apps/data/dev/`** as SoT (infra DBs + OIDC + platform secrets) — checklist in [VPS2_DEV_PLATFORM.md](VPS2_DEV_PLATFORM.md)
- [ ] Install stores needed by platform (PG/Redis/MinIO as required)
- [ ] Install third-party / G24: **OpenProject**, **Lago**, **Langfuse**, **n8n**, **GrowthBook**, LiteLLM / Temporal UI as needed
- [ ] CF `*-dev` consoles → VPS2 tunnel
- [ ] Retarget laptop `~/.asrax/credentials.d/dev.env` (+ Grafana MCP) → VPS2 Vault / bare Grafana
- [ ] Stop treating laptop Kind Vault as credential SoT

### Test (this phase)

- [ ] Grafana MCP `list_datasources` on `https://grafana.asrax.in` (Prom + Loki + Tempo)
- [ ] Prometheus query works; metrics older than ~30d not retained beyond policy
- [ ] Remote Alloy can push to `https://loki.asrax.in` and `https://prometheus.asrax.in`
- [ ] Vault MCP/list: `apps/data/dev/infra/postgres|mongodb|redis|kafka|influxdb|observability` + oidc clients present
- [ ] OpenProject / Lago / Langfuse (whichever installed) login via Keycloak on hub domains
- [ ] Login Grafana via Keycloak domain, not Grafana password

### Test (grown)

- [ ] Phase 10 SSO still holds
- [ ] G9: Grafana not on VPS1
- [ ] Loki PVC not stuck ≥ 80% without janitor run clearing expired chunks
- [ ] Laptop wipe does not lose `apps/data/dev` secrets (SoT on VPS2)

---

## Phase 12 — Scheduled failover drill

### Implement

- [ ] User confirmed drill
- [ ] Replica lag OK
- [ ] Stop VPS1 Kind — **no** DNS edit
- [ ] Promote VPS3 PG + Mongo
- [ ] Time CF LB cutover
- [ ] Human failback using Phase 9 steps

### Test (this phase)

- [ ] CF LB → VPS3 with no DNS click
- [ ] G19 + G15: page, ticks, JWT, positions live. Kafka drop OK

### Test (grown)

- [ ] Domain-only (G26)
- [ ] Phase 4a–4g AM backends still healthy (not market-data-only)
- [ ] All G24 UIs on domain
- [ ] Replica + no auto-failback
- [ ] No Vault sidecar

---

## MCP env lock (with Phase 2 and Phase 6)

### Implement

- [ ] Create `~/.asrax/credentials.d/dev.env` — all URLs `*-dev.asrax.in`
- [ ] Create `prod.env` — `am.asrax.in`, `auth.asrax.in`, …
- [ ] Create `dr.env` — `*-dr.asrax.in`
- [ ] `am ai mcp-sync` loads **one** file per session

### Test

- [ ] Refuse prod/dr MCP if kube context is `am-dev-*`
- [ ] No `localhost` / docker-host in those files

---

## amctl / gitops (after Phase 1, finish with Phase 9)

### Implement

- [ ] `--env dev` → cluster `am-dev-apps`, NS `am-apps-dev`
- [ ] `--env local` **hard-fail** (no `local` token; use `dev`)
- [ ] `--env prod` → `am-prod-apps` / `am-apps-prod`
- [ ] `--env dr` → `am-dr-apps` / `am-apps-dr`
- [ ] Remote `am destroy` / factory-reset **hard-fail**
- [ ] GitOps: apps charts → apps cluster; platform charts → platform cluster
- [ ] **No** Argo Application targeting VPS2 (obs)

### Test

- [ ] Deploy target matches env
- [ ] Values contain **no** localhost / docker-host

---

## Report / PR

- [ ] **Only after every phase Test + Test (grown) is green:** `REPORT.md`
- [ ] PR only if the user asked