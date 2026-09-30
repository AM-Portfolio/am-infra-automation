# GitNexus track — sizing

## Target host (nonprod Contabo)

| Resource | Minimum | Comfortable |
|----------|---------|-------------|
| vCPU | 2 | **4** |
| RAM | 8 GB | **16 GB** |
| Disk | 40 GB SSD | **80 GB** SSD |

Remote LLM only for Hermes (no Ollama on this box unless ≥32 GB).

## RAM split (16 GB)

| Slice | Allocation |
|-------|------------|
| OS + Kind/Docker + Traefik | 2–4 GB |
| GitNexus serve (steady) | 2–4 GB (hard cap ≤8 Gi) |
| GitNexus `analyze` peaks | up to 8 Gi (off-peak / serialized) |
| Hermes (phase 4) | 2–4 GB |
| Headroom | ≥2 GB |

## Hard caps

```bash
# Prevent LadybugDB from eating 80% of host RAM
export GITNEXUS_LBUG_BUFFER_POOL_SIZE=2147483648   # 2 GiB
```

Index Job / analyze: prefer one at a time. Embeddings: weekly/on-demand only (not every push); needs 6–16 Gi if enabled.

## Scale-to-0 reclaim

After phase 1, expect apps/agents NS at 0 replicas so GitNexus + Hermes fit without competing with preprod product pods.
