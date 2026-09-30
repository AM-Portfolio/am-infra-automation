# GitNexus track (Contabo nonprod)

Executable Implement + Test checkboxes for the **shared code-intelligence hub** (GitNexus serve + MCP).  
Product hub repo: **`am-gitnexus`** (extracted from `am-scripts/code-intelligence`).  
**Sizing:** [SIZING.md](SIZING.md).  
**Testing index:** [TESTING.md](TESTING.md) Â· **Report:** [TEST_REPORT.md](TEST_REPORT.md).

## Host facts

- Target: **Contabo nonprod** VPS (not Contabo prod app fleet)
- SSH / kube: `~/.asrax/kubeconfig.preprod` (Contabo nonprod) Â· never commit passwords
- **Hardware target:** **4 vCPU Â· 16 GB RAM** comfortable â€” [SIZING.md](SIZING.md)
- Runtime (phase 2 default): **systemd** `gitnexus serve --host 0.0.0.0 --port 4747` (k8s manifests optional later)
- Data:
  - Hub clone: `/opt/am/gitnexus` (`AM_GITNEXUS_HUB`)
  - Repo clones: `/opt/am/repos`
  - Indexes: `/var/lib/gitnexus` (`GITNEXUS_HOME`)
- Tunnel: **nonprod** CF tunnel â†’ Traefik â†’ gitnexus `:4747`
- UI / MCP: `https://gitnexus.asrax.in` Â· `https://gitnexus.asrax.in/api/mcp`
- Optional: `https://hermes.asrax.in` (phase 4)
- **Keep:** Traefik, cloudflared, Vault, edge NS, all PVCs / Secrets / images
- **Scale-to-0 only (no delete):** `am-apps-dev`, `am-agents-dev`, `am-apps-preprod`, `am-agents-preprod`

## Confirm before scale

Inventory free RAM, edge pods, leftover `deploy/gitnexus` â†’ list â†’ **user confirm** â†’ only then **`kubectl scale --replicas=0`**.  
**Never** `kubectl delete`, wipe `/var/lib/gitnexus`, or run `clear-contabo-dev-ns.sh` / Contabo slim for this track.

## Phase map

| Phase | File | Tests |
|-------|------|-------|
| 0 Inventory | [phase-0.md](phase-0.md) | [tests/phase-0.md](tests/phase-0.md) |
| 1 Scale-to-0 | [phase-1.md](phase-1.md) | [tests/phase-1.md](tests/phase-1.md) |
| 2 Hub + serve + pilot | [phase-2.md](phase-2.md) | [tests/phase-2.md](tests/phase-2.md) |
| 3 Edge cutover | [phase-3.md](phase-3.md) | [tests/phase-3.md](tests/phase-3.md) |
| 4 Hermes | [phase-4.md](phase-4.md) | [tests/phase-4.md](tests/phase-4.md) |
| 5 Consumers + Grown | [phase-5.md](phase-5.md) | [tests/phase-5.md](tests/phase-5.md) |

## Loop

```text
Prereq â†’ Implement â†’ mcp-sync (when needed) â†’ Test â†’ Grown â†’ next
```

Fail â†’ stay on phase. Mark boxes here (not only in laptop TODO.md).

## Obs analogy

| Obs | GitNexus |
|-----|----------|
| `am-obs-platform` | `am-gitnexus` |
| `docs/.../obs/` | `docs/.../gitnexus/` |
| `grafana.asrax.in` | `gitnexus.asrax.in` |

## Hermes hub

Ops modules moved to **[AM-Portfolio/am-hermes](https://github.com/AM-Portfolio/am-hermes)**. Contabo: /opt/am/am-hermes + runtime /opt/am/hermes.
