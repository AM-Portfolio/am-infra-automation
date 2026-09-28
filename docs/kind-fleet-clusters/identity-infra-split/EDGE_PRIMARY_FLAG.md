# GrowthBook — asrax_edge_primary

Ops visibility for Contabo vs DR edge (DNS/LB switch is **GitHub Actions**, not this flag).

| Field | Value |
|-------|--------|
| Key | `asrax_edge_primary` |
| Type | string |
| Default | `prod` |
| Allowed | `prod` (Contabo), `dr` (VPS3) |
| Envs | enable on `production` (and `dev` if useful) |

Create in GrowthBook UI if MCP API key lacks project access. After each `edge-primary` workflow run, set the flag value to match.

Optional: modern-ui ops banner when value is `dr`.
