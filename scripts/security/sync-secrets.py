import subprocess
import json
import os

def run_cmd(cmd, input_data=None):
    if input_data:
        result = subprocess.run(cmd, shell=True, input=input_data, capture_output=True, text=True)
    else:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        
    if result.returncode != 0:
        print(f"Error: {result.stderr}")
        return None
    return result.stdout

def parse_credentials_txt():
    """Reads local credentials.txt and maps to keys expected by the sync engine."""
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    cred_file = os.path.join(root_dir, "infrastructure-secrets", "latest", "credentials.txt")
    
    if not os.path.exists(cred_file):
        print(f"Warning: local credentials file not found at {cred_file}")
        return {}

    mapping = {}
    with open(cred_file, "r") as f:
        for line in f:
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                mapping[k.strip()] = v.strip()
    return mapping

def sync_secrets():
    print("Starting Vault Smart Sync (JSON Stdin Mode)...")
    
    # 1. Fetch Master Secret from Preprod
    cmd_get = 'kubectl --kubeconfig k8s/kubeconfig.vps exec -n vault vault-0 -- /bin/vault kv get -format=json secret/preprod/master'
    raw_data = run_cmd(cmd_get)
    
    vault_master = {}
    if raw_data:
        try:
            master_resp = json.loads(raw_data)
            vault_master = master_resp['data']['data']
            print(f"Fetched master secret from Vault (version {master_resp['data']['metadata']['version']})")
        except Exception as e:
            print(f"Error parsing Vault master secret: {e}")
    else:
        print("Could not fetch master secret from Vault. Will rely on local fallback.")

    # 2. Merge with local credentials.txt
    local_creds = parse_credentials_txt()
    master = {**vault_master}
    
    def merge(vault_key, local_keys):
        if vault_key in master and master[vault_key]: return
        for lk in local_keys:
            if lk in local_creds:
                master[vault_key] = local_creds[lk]
                return

    merge("DB_USER", ["POSTGRESQL_USERNAME", "POSTGRES_USER"])
    merge("DB_PASSWORD", ["POSTGRESQL_PASSWORD", "POSTGRES_PASSWORD"])
    merge("DB_HOST", ["POSTGRESQL_HOST"])
    merge("DB_PORT", ["POSTGRESQL_PORT"])
    merge("DB_NAME", ["POSTGRESQL_DATABASE"])
    merge("MONGO_USER", ["MONGODB_USERNAME"])
    merge("MONGO_PASSWORD", ["MONGODB_PASSWORD"])
    merge("MONGO_HOST", ["MONGODB_HOST"])
    merge("MONGO_PORT", ["MONGODB_PORT"])
    merge("MONGO_DB", ["MONGODB_DATABASE"])
    merge("REDIS_PASSWORD", ["REDIS_PASSWORD"])
    merge("REDIS_HOSTNAME", ["REDIS_HOST"])
    merge("INFLUXDB_TOKEN", ["INFLUXDB_TOKEN"])
    merge("INFLUXDB_ORG", ["INFLUXDB_ORG"])
    merge("INFLUXDB_BUCKET", ["INFLUXDB_BUCKET"])
    merge("KAFKA_USER", ["KAFKA_USERNAME"])
    merge("KAFKA_PASSWORD", ["KAFKA_PASSWORD"])

    # 3. Define Grouped Sinks
    infra_sinks = {
        "postgres": {
            "DB_HOST":     master.get("DB_HOST", "postgresql.infra.svc.cluster.local"),
            "DB_NAME":     master.get("DB_NAME", "postgres"),
            "DB_PASSWORD": master.get("DB_PASSWORD"),
            "DB_PORT":     master.get("DB_PORT", "5432"),
            "DB_USER":     master.get("DB_USER", "postgres")
        },
        "redis": {
            "REDIS_HOSTNAME": master.get("REDIS_HOSTNAME", "redis.infra.svc.cluster.local"),
            "REDIS_PASSWORD": master.get("REDIS_PASSWORD"),
            "REDIS_PORT":     master.get("REDIS_PORT", "6379"),
            "REDIS_URL":      master.get("REDIS_URL")
        },
        "mongodb": {
            "MONGO_HOST":     master.get("MONGO_HOST", "mongodb.infra.svc.cluster.local"),
            "MONGO_PORT":     master.get("MONGO_PORT", "27017"),
            "MONGO_USER":     master.get("MONGO_USER"),
            "MONGO_PASSWORD": master.get("MONGO_PASSWORD"),
            "MONGO_DB":       master.get("MONGO_DB", "am-db")
        },
        "influxdb": {
            "INFLUXDB_URL":   master.get("INFLUXDB_URL", "http://influxdb.infra.svc.cluster.local:8086"),
            "INFLUXDB_TOKEN": master.get("INFLUXDB_TOKEN"),
            "INFLUXDB_ORG":   master.get("INFLUXDB_ORG", "am-portfolio"),
            "INFLUXDB_BUCKET":master.get("INFLUXDB_BUCKET", "market-data")
        },
        "kafka": {
            "KAFKA_BOOTSTRAP_SERVERS": master.get("KAFKA_BOOTSTRAP_SERVERS", "kafka.infra.svc.cluster.local:9092"),
            "KAFKA_USER":              master.get("KAFKA_USER"),
            "KAFKA_PASSWORD":          master.get("KAFKA_PASSWORD")
        },
        "jot": {
            "JWT_SECRET":       master.get("JWT_SECRET"),
            "USER_SERVICE_URL": master.get("USER_SERVICE_URL"),
            "AUTH_SERVICE_URL": master.get("AUTH_SERVICE_URL")
        }
    }

    app_sinks = {
        "auth": {
            "jwt": {
                "JWT_SECRET":       master.get("JWT_SECRET"),
                "USER_SERVICE_URL": master.get("USER_SERVICE_URL"),
                "AUTH_SERVICE_URL": master.get("AUTH_SERVICE_URL")
            }
        }
    }

    # 4. Apply Sinks
    environments = ["preprod", "prod", "local"]
    for env in environments:
        print(f"\n--- Syncing environment: {env} ---")
        for name, payload in infra_sinks.items():
            if any(payload.values()):
                sync_to_vault(f"secret/{env}/infra/{name}", payload)
        for app, sinks in app_sinks.items():
            for sink_name, payload in sinks.items():
                if any(payload.values()):
                    sync_to_vault(f"secret/{env}/apps/{app}/{sink_name}", payload)

    print("\nTotal Synchronization Complete.")

def sync_to_vault(path, payload):
    filtered_payload = {k: v for k, v in payload.items() if v is not None}
    if not filtered_payload: return

    # Use JSON stdin to avoid shell escaping and '@' prefix issues
    json_payload = json.dumps(filtered_payload)
    cmd = f"kubectl --kubeconfig k8s/kubeconfig.vps exec -i -n vault vault-0 -- /bin/vault kv put {path} -"
    
    out = run_cmd(cmd, input_data=json_payload)
    if out:
        print(f"Done syncing {path}. Output: {out.strip()}")
    else:
        print(f"Failed to sync {path}.")

if __name__ == "__main__":
    sync_secrets()
