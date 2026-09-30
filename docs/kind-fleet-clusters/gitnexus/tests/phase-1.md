# Test — GitNexus Phase 1

```bash
# Expect replicas=0; NS still exist
for ns in am-apps-dev am-agents-dev am-apps-preprod am-agents-preprod; do
  kubectl get ns "$ns" >/dev/null 2>&1 || continue
  echo "== $ns =="
  kubectl -n "$ns" get deploy,sts -o custom-columns=KIND:.kind,NAME:.metadata.name,REPLICAS:.spec.replicas
done
# Must still exist (not deleted)
kubectl get ns am-apps-preprod am-agents-preprod am-apps-dev am-agents-dev 2>/dev/null || true
```

- [ ] All listed Deployments/STS in those NS have `replicas=0` (or NS absent on that cluster).
- [ ] Namespaces still present (not deleted).
- [ ] No PVC delete; spot-check `kubectl get pvc -n am-apps-preprod` still lists volumes if any.
- [ ] Traefik / cloudflared pods Ready.
- [ ] `MemAvailable` meets [SIZING.md](../SIZING.md) headroom for Phase 2.
- [ ] UC-04 / UC-05 noted in TEST_REPORT.
- [ ] Confirmed: no `kubectl delete` used in Phase 1.
