# Phase 5 — VPS connect + security (setup + MCP)

**TODO checkboxes:** [TODO.md](TODO.md) Phase 5.  
**Scripts:** [`scripts/vps-security/`](../../scripts/vps-security/) · [README](../../scripts/vps-security/README.md).  
**Do not** start Kind/terraform on a VPS until that host’s Phase 5 Test gate is green.

---

## Hosts

IPs from [VPS/.env](../../../VPS/.env) only (never commit passwords).

| Host | Env key | Role | Root SSH (bootstrap) | Day-2 SSH (`am-ops`) |
|------|---------|------|----------------------|----------------------|
| VPS1 Contabo | `VPS_IP` | prod | `am-vps1` | `am-vps1-ops` |
| VPS2 | `VPS_2_IP` | obs / Grafana | `am-vps2` | `am-vps2-ops` |
| VPS3 | `VPS_3_IP` | DR (≥ 32 GB) | `am-vps3` | `am-vps3-ops` |

WireGuard (5.3): `10.77.1.1` (VPS1) ↔ `10.77.1.2` (VPS3), UDP **51820**. Store ports **:5432** / **:27017** only on WG (iptables `AM-WG-STORES`).

---

## Setup (each host)

1. Prereq: **Phase P** + **Phase 0** Tests green; SSH key reaches the host.
2. Copy scripts (flat — avoid nested directory):

```bash
scp scripts/vps-security/* am-vpsN:/tmp/am-vps-security/
```

3. Root **once**:

```bash
ssh am-vpsN 'bash /tmp/am-vps-security/install-phase51.sh'
```

4. Day-2: reconnect only as `am-ops` via `am-vpsN-ops` (key-only; no password login).

### WireGuard (5.3 only — after key exchange)

Script prints `LOCAL_PUBKEY` on first run. Then:

```bash
ssh am-vps1 'ROLE=vps1 PEER_PUBLIC_IP=<VPS_3_IP> PEER_PUBKEY=<v3pub> bash /tmp/am-vps-security/install-wireguard-vps1-vps3.sh'
ssh am-vps3 'ROLE=vps3 PEER_PUBLIC_IP=<VPS_IP> PEER_PUBKEY=<v1pub> bash /tmp/am-vps-security/install-wireguard-vps1-vps3.sh'
```

---

## What install-phase51.sh puts on the host

| Item | Path / behavior |
|------|-----------------|
| User | `am-ops` — key-only SSH; **no sudoers** |
| Guards | Wrappers `/usr/local/bin/{kubectl,kind,terraform}` → refuse delete/destroy for `am-ops` |
| G1 | `/usr/local/sbin/break-glass-kind.sh` — allowlist only; log `/var/log/am-break-glass.log` |
| State | `/data/am-state` writable by `am-ops`; root kubeconfig `0400` |

G1 allowlist includes: `kind create|delete`, Kind `docker stop|start`, `cloudflared`, `pg_ctl promote`, Mongo `rs.stepUp`.

---

## MCP test matrix (Phase 5)

After `am ai sync` (and `am ai mcp-sync --ide cursor --host-launchers` if Cloudflare launcher missing). Cursor namespace: **`user-cloudflare`**. Auth: `mcp_auth` as `admin@asrax.in` if needed.

| Check | MCP / tool | Expect |
|-------|------------|--------|
| Zone | Cloudflare: list/get zone `asrax.in` | Zone listable |
| Tunnels | Cloudflare: list tunnels | `asrax-prod-tunnel` / obs / dr present as relevant |
| R2 | Cloudflare: list R2 / bucket `asrax-disaster` | Bucket reachable (disaster-path sanity) |

**Not MCP for Phase 5** (shell / provider console only):

- SSH as `am-ops` / root bootstrap
- WireGuard ping / `wg show` / iptables
- Contabo panel, Vault, Keycloak, Grafana (those are later phases)

---

## Shell test matrix (required)

| Check | How | Expect |
|-------|-----|--------|
| Day-2 SSH | `ssh am-vpsN-ops` | Session as `am-ops` |
| No sudo | `sudo true` | Fails |
| Guard | `kubectl delete …` (BatchMode OK) | `am-ops-guard` **REFUSED** |
| G1 path | `ls /usr/local/sbin/break-glass-kind.sh`; log path exists | Only Kind path for create/delete |
| 5.3 RAM | `grep MemTotal /proc/meminfo` | Contabo 32 GB class (SI ≥ 32e9 B) |
| 5.3 WG | ping `10.77.1.1`↔`10.77.1.2` | Both ways |
| 5.3 stores public | Listeners / iptables on eth0/ens3 | `:5432` / `:27017` **not** on public NIC |

---

## Gates

| Subphase | Gate |
|----------|------|
| **5.1** | Green before **Phase 8** (Phases 6–7 may still use live Contabo) |
| **5.2** | Green before **Phase 11** only |
| **5.3** | Green before **Phase 6**; grown: re-check 5.1 guard while Contabo live |

Do **not** wipe Contabo until **Phase 7** (G2).
