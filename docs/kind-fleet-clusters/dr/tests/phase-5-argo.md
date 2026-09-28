# DR Phase 5 gates (Argo waves)

```bash
cd /path/to/am-infra-automation
PYTHONPATH=scripts/kind-fleet python -m phase_gates --env dr --wave 4d
PYTHONPATH=scripts/kind-fleet python -m phase_gates --env dr --wave 4e
PYTHONPATH=scripts/kind-fleet python -m phase_gates --env dr --wave 4f
```

| Wave | Gate | Assert |
|------|------|--------|
| 5b | Argo | Cluster `am-dr-apps` registered; roots/AppSets on main; no auto-sync-all |
| 5c | edge | `am-dr.asrax.in/` 200; `/gateway` 401/403 |
| 5d | identity | login → token → protected **200** on `am-dr` |
| 5e | market | quotes RELIANCE **200** on `am-dr` |
| 5f | apps | portfolio/trade/doc health + list with token |
| 5g | remaining | domain closout; no Vault sidecar |

Domain lock: `*-dr.asrax.in` only (G26/G27). No port-forward.
