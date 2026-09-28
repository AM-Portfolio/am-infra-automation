# Tests — Phase 3 (kube CLI OIDC)

- [ ] Apiserver OIDC configured (issuer = `am-realm`) on target apps/infra cluster
- [ ] `am-ops` via oidc-login: `kubectl get ns` / get pods in `am-apps-*` succeeds on **VPS** API (not `127.0.0.1` for teammates)
- [ ] `am-ops` cannot create ClusterRole (not cluster-admin)
- [ ] `am-admin` break-glass SA kubeconfig still works for operators
- [ ] Headlamp still works **without** sharing a kubeconfig file
- [ ] Teammate onboarding doc does not instruct emailing kubeconfig
