from lib.vps import VPSClient
vps = VPSClient()
if vps.connect():
    print("--- DOCKER STATUS ---")
    _, stdout, _ = vps.execute("docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'", "Docker Audit")
    print(stdout)
    
    print("\n--- K3S STATUS ---")
    # Try multiple ways to get K3s status
    _, stdout, _ = vps.execute("export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; /usr/local/bin/kubectl get svc -A", "K3s Audit")
    print(stdout)
    
    print("\n--- PROCESS LIST (GREP) ---")
    _, stdout, _ = vps.execute("ps aux | grep -E 'mongo|postgres|redis|kafka|vault'", "Process Audit")
    print(stdout)
vps.disconnect()
