import os
import sys

# --- Bootstrap am-scripts ---
# We need to find the am-scripts/src directory to import utilities
AM_SCRIPTS_ENV = os.environ.get("AM_SCRIPTS_PATH")
script_dir = os.path.dirname(os.path.abspath(__file__))

repo_root = os.path.dirname(script_dir)

if AM_SCRIPTS_ENV:
    am_scripts_src = AM_SCRIPTS_ENV
    print(f"ℹ️ Using AM_SCRIPTS_PATH from environment: {am_scripts_src}")
else:
    # Fallback to relative path logic
    am_repos_root = os.path.dirname(repo_root)
    am_scripts_src = os.path.join(am_repos_root, "am-scripts", "src")
    print(f"ℹ️ Calculated am-scripts path: {am_scripts_src}")

if os.path.exists(am_scripts_src):
    if am_scripts_src not in sys.path:
        sys.path.insert(0, am_scripts_src)
    print(f"✅ Successfully bootstrapped am-scripts from: {am_scripts_src}")
else:
    print(f"❌ Error: am-scripts repository not found at {am_scripts_src}")
    print("Please set AM_SCRIPTS_PATH or ensure am-scripts is a sibling to am-infra.")
    # List contents of root for debugging in Docker
    if os.path.exists("/"):
        print(f"DEBUG: Contents of / : {os.listdir('/')}")
    sys.exit(1)

from am_scripts.utils import setup_logger, parse_env, check_namespace_health
from am_scripts.vault import ensure_vault_unsealed
from am_scripts.infra import sync_traefik_config, expose_services

logger = setup_logger("AM_Infra_Expose")

def main():
    env_file = os.path.join(repo_root, ".env.infra")
    apps_yaml = os.path.join(repo_root, "traefik", "apps.yaml")
    infra_yaml = os.path.join(repo_root, "traefik", "infra.yaml")
    keys_file = os.path.join(repo_root, "k8s", "vault", "vault-keys.json")
    
    # Load env
    env_config = parse_env(env_file)
    
    # 0. Adjust Kubeconfig inside Docker to bridge host networking
    if os.environ.get("RUNNING_IN_DOCKER"):
        src_kube = "/root/.kube/config"
        dst_kube = "/tmp/kubeconfig"
        if os.path.exists(src_kube):
            try:
                with open(src_kube, 'r') as f:
                    content = f.read()
                # Replace local addressing with host gateway addressing
                content = content.replace("https://127.0.0.1:", "https://host.docker.internal:")
                content = content.replace("https://localhost:", "https://host.docker.internal:")
                
                # Bypass TLS Verification since cert doesn't match host.docker.internal
                content = content.replace("    server:", "    insecure-skip-tls-verify: true\n    server:")
                
                # Comment out certificate authority to avoid secure flag conflict
                content = content.replace("    certificate-authority-data:", "    # certificate-authority-data:")

                with open(dst_kube, 'w') as f:
                    f.write(content)
                os.environ["KUBECONFIG"] = dst_kube
            except Exception as e:
                pass

    logger.info("AM Service Exposure Automation (using am-scripts)")
    
    # 1. Sync Traefik
    sync_traefik_config(env_config, [apps_yaml, infra_yaml])
    
    # 2. Unseal Vault
    ensure_vault_unsealed(keys_file_path=keys_file)
    
    # 3. Health Check
    check_namespace_health(["infra", "am-apps-preprod", "vault", "monitoring"])
    
    # 4. Expose Services
    expose_services(env_config)

    # 5. Keep alive for Docker execution maintenance
    if os.environ.get("RUNNING_IN_DOCKER"):
        import time
        logger.info("Holding process active for port mapping streams...")
        while True:
            time.sleep(10)

if __name__ == "__main__":
    main()
