# GitNexus — Phase 1 (Scale-to-0 only — NO deletes)

Tests: [tests/phase-1.md](tests/phase-1.md) · Sizing: [SIZING.md](SIZING.md).

## Prereq

Phase 0 green + **user confirm** of NS list.

## Hard rule (nonprod VPS)

| Allowed | Forbidden |
|---------|-----------|
| `kubectl scale … --replicas=0` on Deployments / StatefulSets | `kubectl delete` (pods, NS, PVC, deploy, …) |
| Leave NS, PVCs, images, Secrets, ConfigMaps in place | `clear-contabo-dev-ns.sh` (**force-deletes pods** — do not use) |
| Scale back later with `--replicas=1` | `contabo_slim_scale0_only.sh` for this track (scale-only but **too broad**: infra-preprod, billing, am-ai, growthbook, kafka, even some prod agent names) |
| | Wipe `/opt/am/*`, `/var/lib/gitnexus`, Docker volumes |

AppSets already `ignoreDifferences` on `/spec/replicas` — scale sticks without deleting Applications.

## Deploy model (locked)

| Step | Tool | Refuse |
|------|------|--------|
| Scale apps/agents | **`kubectl scale --replicas=0` only** (four NS below) | Any delete; clear-contabo-dev-ns; contabo_slim for this track |
| Edge | Leave Ready | Scaling Traefik / cloudflared / Vault |

## Implement

- [x] Confirm kubeconfig: Contabo via `kubeconfig.preprod` (also dig Kind earlier).
- [x] **Scale to 0 only** on dig Kind (2026-09-28): all Deployments in four NS → replicas=0; NS retained; no delete.
- [x] No STS in those NS (scale sts no-op).
- [x] Contabo nonprod scale (`kubeconfig.preprod`, 2026-09-28): four NS → 0; last 8 apps-preprod deploys scaled.
- [x] Verified NS still Active.
- [x] Contabo MemAvailable ~29 Gi after scale (31 Gi host).

## Test

See [tests/phase-1.md](tests/phase-1.md).

## Grown

- [ ] Apps/agents stay at 0 until operator scales back to 1.
- [ ] Edge still serving other hostnames.
- [ ] NS / PVC / Secrets still present (`kubectl get ns,pvc -A` sample).

## Refuse

- Scaling `infra` / Vault / Traefik / cloudflared to 0.
- Force-deleting pods after scale (unnecessary; scale-to-0 already stops them).
- Relying on `preprod_set_auto(false)` alone (does not stop pods).
- Running Contabo “slim” or “clear-contabo-dev” scripts for this GitNexus reclaim.
