# VPS security (Phase 5.x)

Bootstrap `am-ops` + G1 break-glass on Contabo / VPS hosts **before** Kind.

| File | Role |
|------|------|
| `install-phase51.sh` | Root once: `am-ops`, wrappers at `/usr/local/bin` (BatchMode-safe), G1, `/data/am-state`, log, kubeconfig `0400` |
| `am-ops-guard-*` | Refuse `kubectl delete` / `kind create\|delete` / `terraform destroy` for `am-ops`; passthrough for root |
| `break-glass-kind.sh` | Root allowlist → `/var/log/am-break-glass.log` |
| `install-wireguard-vps1-vps3.sh` | WG VPS1↔VPS3 (`10.77.1.1`↔`10.77.1.2`) + iptables store-port policy |

```bash
# Flat copy (avoid nested scp of the directory):
scp scripts/vps-security/* am-vps1:/tmp/am-vps-security/
ssh am-vps1 'bash /tmp/am-vps-security/install-phase51.sh'

# WireGuard (after key exchange — script prints LOCAL_PUBKEY on first run):
ssh am-vps1 'ROLE=vps1 PEER_PUBLIC_IP=<vps3> PEER_PUBKEY=<v3pub> bash /tmp/am-vps-security/install-wireguard-vps1-vps3.sh'
ssh am-vps3 'ROLE=vps3 PEER_PUBLIC_IP=<vps1> PEER_PUBKEY=<v1pub> bash /tmp/am-vps-security/install-wireguard-vps1-vps3.sh'

# Day-2: am-vps1-ops / am-vps2-ops / am-vps3-ops
```
