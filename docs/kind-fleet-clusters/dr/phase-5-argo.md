# DR — Phase 5 (Argo deploy / sync / verify)

Skill: `phase-4-apps.md` (waves) · tests [`tests/phase-4.md`](tests/phase-4.md) · index [DR_DEPLOY.md](../DR_DEPLOY.md).

**Prereq:** [phase-4.md](phase-4.md) Vault + G25 green. Access still **off**.

**Naming:** Waves reuse prod letters as **5c–5g** (gateway → identity → market → portfolio… → remaining). VPS security remains [phase-5.md](phase-5.md) (5.1).

## Deploy model (locked)

| Step | Tool | Refuse |
|------|------|--------|
| **5a** Register + project | Argo cluster + AppProject | — |
| **5b** Enroll roots / AppSets | Git + ApplicationSets | automated sync-all |
| **5c–5g** Product + agents | **Argo sync** `targetRevision: main` | Terraform AM Deployments; default `am deploy` |

## Implement

### 5a — Register cluster

- [x] Register `am-dr-apps` in Argo (API docker `172.18.0.3:6443` **Successful**; host `:6444` for laptop).
- [x] AppProject `am-dr` destinations → `am-dr-apps` / `am-apps-dr`+`am-agents-dr`+`edge`. *(git: `projects/am-dr.yaml`)*

### 5b — Enroll

- [x] ApplicationSets `am-apps-dr-fleet` / `am-agents-dr-fleet` on platform Argo (30 child Apps, Manual sync).
- [x] imageValues + chart + values → `main`; Manual sync; **no** automated sync-all.
- [x] GHCR pull secrets `ghcr-creds` / `github-registry-secret` in apps+agents+edge.
- [ ] Image pins from `dr/image-tags/` (promote-from-prod via workflow when needed).
- [x] Argo GitHub `repo-creds` (live `gh` PAT) — sample `am-gateway-dr` → OutOfSync/Missing (ready to sync).

### 5c — Gateway / UI / proxy

- [x] Sync: gateway + AI gateway + modern-ui + asrax-proxy (+ api-gateway) — pods **Ready**.
- [x] Apps Traefik (edge NS, NodePort 30080) + infra bridge IP (`172.18.0.3`).
- [x] Middlewares via TF `kind-fleet/dr/apps` (`dr-global-cors` / `dr-strip-prefix`).
- [x] CF tunnel / DNS for `am-dr.asrax.in` (CNAME + tunnel ingress; UI 200 / gateway 401).

### 5d — Identity

- [x] Sync: `am-identity` (+ notification Ready; subscription blocked on PG table owner for migrations).
- [x] Hard gate: `PYTHONPATH=scripts/kind-fleet python -m phase_gates --env dr --wave 4d` → PASS (`/identity/admin/roles=200`, iss=`auth-dr`).

### 5e — Market

- [x] Sync: `am-market-data` — pod **1/1 Ready** (gitops [#14](https://github.com/AM-Portfolio/am-gitops/pull/14): actuator probes; AppSet has no `values.dr.yaml` so chart defaulted `/health` → 500).
- [x] Quote: `GET .../quotes?symbols=RELIANCE` → **200** on `am-dr` (cache hit).
- [x] Hard gate: `phase_gates --env dr --wave 4e` → **PASS**.

**Operator path (same as prod):** gitops PR → `argocd app sync` → `phase_gates`. No new `dr-phase*.sh`.

### 5f — Portfolio / trade / doc

- [ ] Sync: portfolio → trade → doc → news/analysis via Argo only (gitops extras if CSI/ingress gaps — mirror prod overlays).
- [ ] Gate: `phase_gates --env dr --wave 4f` → PASS.

**Operator path (locked):** gitops/TF PR → `argocd app sync` → `phase_gates`. AppSets load `values.prod.yaml` after `values.dr.yaml` (missing OK). **Refuse** new `dr-phase*.sh`.

### 5g — Remaining + agents

- [ ] Sync remaining apps + agents (batched); Postman / domain closout.
- [ ] Spot-check: no Vault sidecar; CSI remounts OK after extras.
- [ ] Gate: `phase_gates --env dr --wave 4g` → PASS.

## Test — app / API host matrix

| Path / host | Wave | Expected |
|-------------|------|----------|
| `https://am-dr.asrax.in/` | 5c | UI 200 or auth challenge |
| `https://am-dr.asrax.in/gateway` | 5c | health or **401** without token |
| Login → token → protected API | 5d | **200** with token |
| Market quote | 5e | quote on domain |
| Portfolio / trade / doc | 5f | domain smoke |
| Remaining apps + agents | 5g | domain / Postman |
| `https://auth-dr.asrax.in` | all | without Access cookie |

### Checks

- [ ] After each wave: pods Ready in `am-apps-dr` / `am-agents-dr`.
- [x] **5d** + **5e** gates green; **5g** closout still open.
- [ ] Isolation: **no** `am-apps-prod` on VPS3.
- [ ] Access still off through all waves.
- [ ] Image pins not `latest`.

## Grown

- [ ] CSI still OK (Vault not re-seeded per wave).
- [ ] 5d gate still holds after later waves.
- [ ] Ready for [phase-6-g20-lb.md](phase-6-g20-lb.md).

## Stop if fail / Refuse

Stay on failing wave. No terraform for AM Deployments. No `am deploy` except break-glass. No Vault re-seed per wave. No Access enforce mid Phase 5.
