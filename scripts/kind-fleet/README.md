# Kind-fleet operator scripts

## Ownership (hard rule)

| Concern | Owner | Forbidden here |
|---------|-------|----------------|
| Kind, stores, Vault seed, CSI, platform Helm, edge DNS/tunnel, apps Traefik bridge | Terraform `kind-fleet/{env}/{infra,stores,platform,vault-apps,apps,edge}` | One-shot `vault kv` writes, loose bridge YAML |
| App/agent desired state (Vault paths, hostAliases, ingress, image pins) | **am-gitops** Application YAML | `kubectl replace` Application from `/tmp` or tarballs |
| Sync | Argo (roots watch `apps/` + `agents/`) | `wave_*_sync.py`, closout sync loops |
| Debug / smoke | This folder (`_debug_*`, `_vault_*` read probes, `_argo_*`, `phase_gates/`) | Live surgery that becomes SoT |

**New `_fix_*` scripts are forbidden.** Fix lands in a Terraform PR or an am-gitops PR, then Argo sync. Cloudflare MCP is emergency-only — backfill the same host into TF `https_names` / `extra_fqdns` the same day.

**Contract tests** (FQDN / bridge Host match / n8n main selector / vault catalog): run `terraform test` under `terraform/modules/core/kind-fleet-contracts` and `terraform/modules/core/apps-vault-seed` — not this folder.

## Operator path

1. Edit **am-gitops** (or TF for edge/bridge/Vault seed).
2. Merge to `main`.
3. Argo sync the Application (UI or `argocd app sync`).
4. Use `_debug_*` / `_vault_*` / `phase_gates/` only to verify — not to patch live desired state.

Wipe/reseed: `terraform/kind-fleet/*/apps/scripts/fresh-redeploy.ps1` applies **gitops from the repo checkout** + G25/vault-apps TF. Do not feed it Application JSON from `/tmp` or `_gitops-*.tgz`.

## Keep vs retired

- **Keep:** `phase_gates/`, `_debug_*`, `_vault_*` (read probes), `_argo_*` / `_closout_verify*`, `_qa_*`, `_check_*`, `_status_*`, `_spc_dump.sh`
- **Retired:** `_retired/` — wave sync, `_fix_*`, hostAliases/pullSecrets patchers, `sync_keycloak_admin_to_vault.py` (SoT = platform `write_keycloak_admin_env` + vault-apps seed), superseded `_apps_bridge_hosts.yaml`
