import subprocess
import json
import sys
import os
from pathlib import Path

def run_cmd(cmd):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        return None
    return result.stdout

def pull_secrets(env="preprod"):
    print(f"--- Pulling Vault Secrets for environment: {env} ---")
    
    # Define what we want to pull
    infra_sinks = ["postgres", "redis", "influxdb", "mongodb", "kafka"]
    app_sinks = {
        "auth": ["jwt"]
    }

    all_secrets = {}

    # 1. Pull Infra
    for sink in infra_sinks:
        path = f"secret/{env}/infra/{sink}"
        cmd = f"kubectl --kubeconfig k8s/kubeconfig.vps exec -n vault vault-0 -- /bin/vault kv get -format=json {path}"
        raw = run_cmd(cmd)
        if raw:
            data = json.loads(raw)['data']['data']
            all_secrets.update(data)
            print(f"Fetched infra/{sink}")

    # 2. Pull App Specific
    for app, sinks in app_sinks.items():
        for sink in sinks:
            path = f"secret/{env}/apps/{app}/{sink}"
            cmd = f"kubectl --kubeconfig k8s/kubeconfig.vps exec -n vault vault-0 -- /bin/vault kv get -format=json {path}"
            raw = run_cmd(cmd)
            if raw:
                data = json.loads(raw)['data']['data']
                all_secrets.update(data)
                print(f"Fetched apps/{app}/{sink}")

    # 3. Write .env files
    repo_roots = {
        "am-auth": Path("..") / "am-auth" / "am" / ".env",
        "am-market": Path("..") / "am-market" / ".env.secrets"
    }

    for repo, env_path in repo_roots.items():
        if env_path.parent.parent.exists():
            print(f"Updating {repo} secrets at {env_path}...")
            content = ""
            for k, v in sorted(all_secrets.items()):
                content += f"{k}={v}\n"
            
            with open(env_path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"SUCCESS: Created {env_path}")
        else:
            print(f"WARNING: Skip {repo}: Repository not found at expected location.")

if __name__ == "__main__":
    env_choice = sys.argv[1] if len(sys.argv) > 1 else "preprod"
    pull_secrets(env_choice)
