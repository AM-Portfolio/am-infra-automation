# DR — Phase 4 (Vault sync only)

Skill: `phase-4-apps.md` (vault/G25 section) · tests [`tests/phase-4.md`](tests/phase-4.md).

**This phase does not deploy product pods.** Argo enroll + sync waves are [phase-5-argo.md](phase-5-argo.md).

**Seed coupling:** `vault-apps` requires `/data/am-state/credentials/dr/keycloak-admin.env` (compat symlink `dr-keycloak-admin.env`) written by platform apply.

## Prereq

Phase 3e green; Phase 2 DBs seeded. Access still **off**.

## Deploy model (locked)

| Step | Tool | Refuse |
|------|------|--------|
| **4** Vault + G25 | **`terraform apply`** `kind-fleet/dr/vault-apps` + G25 on **existing** `am-dr-apps` | Hand-seed Vault; Argo writing Vault; product Deployments; **`kind delete` to “own” the cluster** |

**Cluster adopt:** If G1 already created `am-dr-apps` and TF state is empty, run [`scripts/kind-fleet/adopt-kind-cluster.sh`](../../../scripts/kind-fleet/adopt-kind-cluster.sh) (`terraform import`) — **never** delete/recreate for CSI/NS/SA apply.

## Implement

### Apps cluster + SA

- [x] Confirm `am-dr-apps` API **:6444**.
- [x] NS `am-apps-dr` + `am-agents-dr` + `edge`; SA `am-backend-sa`.

### Vault-apps (one apply)

- [x] `kind-fleet/dr/vault-apps` apply — catalog infra + all services under `apps/data/dr/*` (36 services).
- [x] Hosts rewritten for DR (`postgres-dr` / `mongodb-dr` / `auth-dr` / `influxdb-dr`; OIDC issuer `https://auth-dr.asrax.in/realms/am-realm`).
- [x] UI base `https://am-dr.asrax.in`.

### G25 CSI

- [x] CSI chart + vault-csi-provider on `am-dr-apps`.
- [x] `auth/kubernetes-apps` / role `am-backend-role`.
- [x] Vault addr `https://vault-dr.asrax.in`; injector **off**.
- [x] CSI login Job → `LOGIN_AND_READ_OK` (read `apps/data/dr/infra/postgres`).

### Fleet overlay (git, no pod sync yet)

- [x] Confirm `overlays/dr/fleet-common.yaml` points at `vault-dr.asrax.in` + CSI + `am-backend-role`.
- [x] Confirm `overlays/dr/extra-*` CSI remaps present (secret→apps, empty CSI off, mcp-gateway path) — land before Phase 5 sync.

## Test — Vault only

- [x] Vault paths `apps/data/dr/infra/*` + catalog `services/*` present after **one** apply.
- [x] CSI login → `LOGIN_AND_READ_OK`; **no** product pods required yet.
- [x] Grep fail: localhost / port-forward / prod Contabo as SoT in seed hosts (`POSTGRES_HOST=postgres-dr.asrax.in`).
- [x] Gate: `PYTHONPATH=scripts/kind-fleet python -m phase_gates --env dr --wave 4a` → **PASS**.

## Grown

- [x] CSI still OK (Vault not re-seeded per service).
- [x] Ready for **Phase 5 Argo** — do not sync product apps until Phase 4 green.

## Stop if fail / Refuse

Stay on Phase 4. No Argo product sync. No terraform AM Deployments. No Access enforce.
