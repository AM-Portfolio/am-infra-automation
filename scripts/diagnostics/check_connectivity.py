import os
import sys
import subprocess
import socket
import time
import psutil

# Fix for Windows terminal encoding issues (emojis)
if sys.platform == "win32":
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

# --- Path Bootstrapping ---
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(os.path.dirname(SCRIPT_DIR))
SCRIPTS_DIR = os.path.join(ROOT_DIR, "scripts")

# Add shared/lib and other packages to path
sys.path.append(os.path.join(SCRIPTS_DIR, "shared"))

# Lazy imports to ensure dependencies exist
def lazy_import(module_name, install_name=None):
    install_name = install_name or module_name
    try:
        if module_name == 'kafka':
            return __import__('kafka')
        return __import__(module_name)
    except ImportError:
        print(f"Installing missing dependency: {install_name}...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", install_name])
        return __import__(module_name)

redis = lazy_import('redis')
requests = lazy_import('requests')
psycopg2 = lazy_import('psycopg2', 'psycopg2-binary')
pymongo = lazy_import('pymongo')
kafka_module = lazy_import('kafka', 'kafka-python')
influxdb_client = lazy_import('influxdb_client')
pymongo = lazy_import('pymongo')
kafka_module = lazy_import('kafka', 'kafka-python')
influxdb_client = lazy_import('influxdb_client')

# --- Configuration (Simplified Environments) ---
AM_ENV = os.environ.get("AM_ENV", "local").lower()

ENV_CONFIGS = {
    "local": {
        "name": "Local (Kind)",
        "host": "localhost",
        "ports": {"mongo": 27017, "postgres": 5432, "redis": 6379, "kafka": 9092, "influx": 8086, "vault": 8200, "traefik": 8080, "grafana": 3000, "prometheus": 9090, "loki": 3100, "authentik": 9443}
    },
    "preprod": {
        "name": "Pre-Production (VPS)",
        "host": "203.174.22.129",
        "ports": {"mongo": 27017, "postgres": 5432, "redis": 6379, "kafka": 9092, "influx": 8086, "vault": 8200, "traefik": 8080, "grafana": 3000, "prometheus": 9090, "loki": 3100, "authentik": 9443}
    }
}

# If the user is running `preprod` but via a tunnel on localhost, allow host override
INFRA_HOST = os.environ.get("INFRA_HOST", ENV_CONFIGS.get(AM_ENV, ENV_CONFIGS["local"])["host"])
CONF = ENV_CONFIGS.get(AM_ENV, ENV_CONFIGS["local"])
CONF["host"] = INFRA_HOST

# --- Service Bridge Configuration ---
# Map logical service name to K8s resource for port-forwarding
BRIDGE_MAP = {
    "mongo":      {"ns": "infra",      "svc": "mongodb",           "port": 27017},
    "postgres":   {"ns": "infra",      "svc": "postgresql",        "port": 5432},
    "redis":      {"ns": "infra",      "svc": "redis-master",      "port": 6379},
    "kafka":      {"ns": "infra",      "svc": "kafka",             "port": 9092},
    "influx":     {"ns": "infra",      "svc": "influxdb-influxdb2","port": 8086, "target_port": 80}, # local 8086 -> svc 80
    "vault":      {"ns": "vault",      "svc": "vault",             "port": 8200},
    "traefik":    {"ns": "infra",      "svc": "traefik",           "port": 8080},
    "grafana":    {"ns": "monitoring", "svc": "grafana",           "port": 3000, "target_port": 80}, # local 3000 -> svc 80
    "prometheus": {"ns": "monitoring", "svc": "prometheus-server", "port": 9090, "target_port": 80},
    "loki":       {"ns": "monitoring", "svc": "loki",              "port": 3100},
    "authentik":  {"ns": "identity",   "svc": "authentik-server",  "port": 9001, "target_port": 80},
}

# --- Coloring Helpers ---
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

# --- Bridge Helpers ---

def is_port_listening(port):
    """Check if any process is listening on the port."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.2)
        return s.connect_ex(('127.0.0.1', port)) == 0

def kill_port_occupant(port):
    """Find and kill any stale kubectl/socat process on the target port."""
    cleared = False
    for conn in psutil.net_connections(kind='inet'):
        if conn.laddr.port == port and conn.status == 'LISTEN':
            try:
                p = psutil.Process(conn.pid)
                p_name = p.name().lower()
                if 'kubectl' in p_name or 'socat' in p_name:
                    print(f"  {Colors.WARNING}⚠️ Force-clearing stale bridge ({p_name}, PID {conn.pid}) on port {port}...{Colors.ENDC}")
                    p.terminate()
                    p.wait(timeout=5)
                    cleared = True
                else:
                    print(f"  {Colors.FAIL}🚫 Port {port} is occupied by non-bridge process: {p_name} (PID {conn.pid}).{Colors.ENDC}")
                    return False, False # Occupied by something else
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
    return True, cleared

def start_bridge(service_key):
    """Launch a background kubectl port-forward for the service."""
    if service_key not in BRIDGE_MAP: return False
    info = BRIDGE_MAP[service_key]
    local_port = info["port"]
    target_port = info.get("target_port", local_port)
    
    # Pre-check: Does the service even exist?
    try:
        check_cmd = ["kubectl", "get", "svc", "-n", info["ns"], info["svc"]]
        subprocess.check_output(check_cmd, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError:
        print(f"  {Colors.FAIL}❌ Missing Resource: Service '{info['svc']}' NOT FOUND in namespace '{info['ns']}'.{Colors.ENDC}")
        return False

    print(f"  {Colors.OKBLUE}🌉 Bridging {info['ns']}/{info['svc']} -> Localhost:{local_port}...{Colors.ENDC}")
    
    cmd = ["kubectl", "port-forward", "-n", info["ns"], f"svc/{info['svc']}", f"{local_port}:{target_port}"]
    
    try:
        if sys.platform == "win32":
            subprocess.Popen(cmd, creationflags=subprocess.CREATE_NO_WINDOW)
        else:
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        
        # Freshness stabilization: Wait up to 5 seconds for the tunnel to REALLY work
        for i in range(10):
            time.sleep(0.5)
            if is_port_listening(local_port):
                # Try a true connection check
                try:
                    with socket.create_connection(('127.0.0.1', local_port), timeout=1):
                        print(f"  {Colors.OKGREEN}✅ Bridge operational on port {local_port}{Colors.ENDC}")
                        return True
                except:
                    pass
        print(f"  {Colors.FAIL}❌ Bridge failed to respond on port {local_port}{Colors.ENDC}")
    except Exception as e:
        print(f"  {Colors.FAIL}❌ Error starting bridge: {e}{Colors.ENDC}")
    return False

def ensure_accessible(service_key, force=False):
    """Smart check: If not listening OR force=True -> Kill occupant -> Restart."""
    # Special Handling: If we are on Localhost, we might have a permanent bridge (Docker)
    # We should only try to "bridge" if we can't actually talk to the service.
    
    if service_key not in BRIDGE_MAP: return
    port = BRIDGE_MAP[service_key]["port"]
    
    # 1. Quick check: Is it already working?
    if not force:
        if is_port_listening(port):
            try:
                # Try a very quick low-level connect
                with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                    return # Already up and responsive (likely via am-port-exposer)
            except:
                pass # Port is listening but unresponsive, proceed to restart
    
    if force:
        print(f"  {Colors.WARNING}🔄 Force-refreshing bridge for {service_key}...{Colors.ENDC}")

    # 2. If we get here, we need a bridge. Kill kubectl/socat on that port if they exist.
    ok_to_proceed, was_killed = kill_port_occupant(port)
    if ok_to_proceed:
        start_bridge(service_key)

# --- Layer Detection (Early) ---
def get_target_layer():
    for arg in sys.argv:
        if arg.startswith("--layer="):
            return arg.split("=")[1].lower()
    return "all"

TARGET_LAYER = get_target_layer()

# --- Flexible Credential Resolver ---
def resolve_credentials(target_layer="all"):
    creds = {}
    local_creds_path = os.path.join(ROOT_DIR, "infrastructure-secrets", "latest", "credentials.txt")
    local_env_path = os.path.join(ROOT_DIR, ".env.infra")

    creds_metadata = {}
    if os.path.exists(local_creds_path) or os.path.exists(local_env_path):
        target_file = local_creds_path if os.path.exists(local_creds_path) else local_env_path
        source_tag = "[LOCAL]" if "credentials.txt" in target_file else "[ENV]"
        with open(target_file, "r", encoding="utf-8", errors="ignore") as f:
            current_section = "GENERAL"
            for line in f:
                raw_line = line.strip()
                if not raw_line or "LAST SYNCED" in raw_line.upper(): 
                    continue
                
                # Check for major sections
                first_char = line[0] if line else ""
                if first_char and first_char not in [" ", "\t", "➜", "→", "━", "="]:
                    current_section = raw_line.upper().replace(" ", "_")
                
                if any(x in raw_line for x in ["➜", "→"]):
                    parts = raw_line.split("➜") if "➜" in raw_line else raw_line.split("→")
                    service_name = parts[0].strip().upper().replace(" ", "_").replace("-", "_")
                    if service_name: current_section = service_name

                # Handle K:V and K=V
                k, v = None, None
                if ":" in raw_line: k, v = raw_line.split(":", 1)
                elif "=" in raw_line: k, v = raw_line.split("=", 1)
                
                if k and v:
                    label = k.strip().upper().replace(" ", "_").replace("-", "_")
                    val = v.strip().strip('"').strip("'")
                    
                    if not val or any(x in val.lower() for x in ["run", "vault kv", "secret/", "password :"]):
                        val = None 
                    
                    if val is not None:
                        label = label.upper()
                        final_key = label
                        
                        # Contextual mapping based on section header
                        sec = current_section.upper()
                        if "PASSWORD" in label or "AUTHENTICATION" in label or label == "POSTGRESQL" or label == "REDIS" or label == "MONGODB":
                            if "POSTGRES" in sec or label == "POSTGRESQL": final_key = "POSTGRESQL_PASSWORD"
                            elif "MONGO" in sec or label == "MONGODB":     final_key = "MONGODB_PASSWORD"
                            elif "INFLUX" in sec or label == "INFLUXDB":    final_key = "INFLUXDB_TOKEN"
                            elif "REDIS" in sec or label == "REDIS":        final_key = "REDIS_PASSWORD"
                            elif "VAULT" in sec:                           final_key = "VAULT_ROOT_TOKEN"
                        
                        if "USER" in label:
                            if "MONGO" in sec:     final_key = "MONGODB_USERNAME"
                            elif "POSTGRES" in sec: final_key = "POSTGRESQL_USERNAME"
                        
                        if label == "ADMIN_TOKEN": final_key = "VAULT_ROOT_TOKEN"
                        if label == "KAFKA":       final_key = "KAFKA_BOOTSTRAP"
                        
                        creds[final_key] = val
                        creds_metadata[final_key] = source_tag
        
        # 2. Hardcoded fallback for known patterns (if sync fails)
        if "MONGODB_PASSWORD" not in creds or not creds["MONGODB_PASSWORD"]:
           # Try one last regex-like sweep if still missing
           with open(target_file, "r", encoding="utf-8", errors="ignore") as f:
               for line in f:
                   if "MongoDB" in line and ":" in line:
                       creds["MONGODB_PASSWORD"] = line.split(":", 1)[1].strip()
                       creds_metadata["MONGODB_PASSWORD"] = f"{source_tag} (Fallback)"

        # 3. Automated Vault Sync
        vault_token = creds.get("VAULT_ROOT_TOKEN") or os.environ.get("VAULT_TOKEN")
        if vault_token:
            try:
                ensure_accessible("vault")
                mounts_url = f"http://localhost:{CONF['ports']['vault']}/v1/sys/mounts"
                headers = {"X-Vault-Token": vault_token}
                m_resp = requests.get(mounts_url, headers=headers, timeout=1)
                
                if m_resp.status_code == 200:
                    mounts = m_resp.json()
                    if "secret/" in mounts or "secret" in mounts:
                        scan_paths = ["infra", "infra/database/mongodb", "infra/database/postgresql", 
                                      "infra/database/redis", "infra/db-users/mongodb/admin", "infra/db-users/postgresql/admin"]
                        
                        print(f"  {Colors.OKCYAN}🔄 Syncing missing secrets from Vault...{Colors.ENDC}")
                        for p in scan_paths:
                            url = f"http://localhost:{CONF['ports']['vault']}/v1/secret/data/{p}"
                            resp = requests.get(url, headers=headers, timeout=1)
                            if resp.status_code == 200:
                                data = resp.json().get('data', {}).get('data', {})
                                for vk, vv in data.items():
                                    full_vk = vk.upper().replace("-", "_")
                                    # Overwrite if missing OR if we want to confirm vault source
                                    if full_vk not in creds or not creds[full_vk]:
                                        creds[full_vk] = vv
                                        creds_metadata[full_vk] = f"{Colors.OKGREEN}[VAULT]{Colors.ENDC}"
            except Exception as e:
                print(f"  {Colors.WARNING}⚠️ Vault sync failed: {e}{Colors.ENDC}")

    # Log individual field sources (Contextual)
    important_keys = []
    if target_layer in ["data-stores", "datastores", "all"]:
        important_keys += ["POSTGRESQL_PASSWORD", "MONGODB_PASSWORD", "INFLUXDB_TOKEN", "REDIS_PASSWORD", "KAFKA_BOOTSTRAP"]
    if target_layer in ["monitoring", "all"]:
        important_keys += ["INFLUXDB_TOKEN"]
        if "GRAFANA_PASSWORD" in creds: important_keys.append("GRAFANA_PASSWORD")
    if target_layer in ["identity", "foundation", "all"]:
        important_keys += ["VAULT_ROOT_TOKEN"]

    # Remove duplicates while preserving order
    important_keys = list(dict.fromkeys(important_keys))

    if important_keys:
        print(f"\n{Colors.OKCYAN}🔑 Credential Origin Map ({target_layer.upper()}):{Colors.ENDC}")
        # Add Kafka as inferred if not in creds but requested
        if "KAFKA_BOOTSTRAP" in important_keys and "KAFKA_BOOTSTRAP" not in creds:
            creds["KAFKA_BOOTSTRAP"] = f"{CONF['host']}:{CONF['ports']['kafka']}"
            creds_metadata["KAFKA_BOOTSTRAP"] = f"{Colors.OKBLUE}[INFERRED]{Colors.ENDC}"

        for k in important_keys:
            source = creds_metadata.get(k, f"{Colors.FAIL}[MISSING]{Colors.ENDC}")
            val_status = f"{Colors.OKGREEN}Active{Colors.ENDC}" if k in creds and creds[k] else f"{Colors.FAIL}Empty{Colors.ENDC}"
            print(f"  {k:20} -> {source:30} | {val_status}")

    return creds, "[RESOLVED]"

CREDS, CREDS_TAG = resolve_credentials(TARGET_LAYER)

DATABASE_CONFIG = {
    'mongo': {'host': CONF['host'], 'port': CONF['ports']['mongo'], 'user': CREDS.get('MONGODB_USERNAME', 'admin'), 'pass': CREDS.get('MONGODB_PASSWORD', '')},
    'postgres': {'host': CONF['host'], 'port': CONF['ports']['postgres'], 'user': CREDS.get('POSTGRESQL_USERNAME', 'postgres'), 'pass': CREDS.get('POSTGRESQL_PASSWORD', ''), 'db': 'postgres'},
    'redis': {'host': CONF['host'], 'port': CONF['ports']['redis'], 'pass': CREDS.get('REDIS_PASSWORD', '')},
    'kafka': {'host': CONF['host'], 'port': CONF['ports']['kafka']},
    'influx': {'host': CONF['host'], 'port': CONF['ports']['influx'], 'token': CREDS.get('INFLUXDB_TOKEN', ''), 'org': 'am-portfolio'},
    'vault': {'host': CONF['host'], 'port': CONF['ports']['vault'], 'token': CREDS.get('VAULT_ROOT_TOKEN', '')},
    'traefik': {'host': CONF['host'], 'port': CONF['ports']['traefik']},
    'grafana': {'host': CONF['host'], 'port': CONF['ports']['grafana']},
    'prometheus': {'host': CONF['host'], 'port': CONF['ports']['prometheus']},
    'loki': {'host': CONF['host'], 'port': CONF['ports']['loki']},
}

def print_status(service, status, target, msg=""):
    color = Colors.OKGREEN if status == "OK" else (Colors.WARNING if status == "WARN" else Colors.FAIL)
    print(f"  {Colors.BOLD}[{service.upper().ljust(10)}]{Colors.ENDC} {color}{status.ljust(5)}{Colors.ENDC} | {Colors.OKBLUE}{target.ljust(25)}{Colors.ENDC} | {msg}")


# --- LAYER 1: FOUNDATION ---
def check_foundation():
    print(f"\n{Colors.BOLD}{Colors.HEADER}=== LAYER 1: FOUNDATION ==={Colors.ENDC}")
    ensure_accessible("traefik")
    target = f"{DATABASE_CONFIG['traefik']['host']}:{DATABASE_CONFIG['traefik']['port']}"
    try:
        r = requests.get(f"http://{target}/api/version", timeout=2)
        if r.status_code == 200:
            print_status("Traefik", "OK", target, f"Dashboard API v{r.json().get('Version')}")
        else:
            print_status("Traefik", "WARN", target, f"Status code {r.status_code}")
    except Exception:
        print_status("Traefik", "FAIL", target, "API Unreachable")


# --- Test Helpers ---
def test_with_retry(service_key, test_fn, target_str):
    ensure_accessible(service_key)
    try:
        msg = test_fn()
        print_status(service_key, "OK", target_str, msg if msg else "Connected")
    except Exception as e:
        if AM_ENV == "local":
            ensure_accessible(service_key, force=True)
            try:
                msg = test_fn()
                print_status(service_key, "OK", target_str, (msg if msg else "Connected") + " (Retry)")
            except Exception as e2:
                print_status(service_key, "FAIL", target_str, f"Error: {str(e2)}")
        else:
            print_status(service_key, "FAIL", target_str, f"Error: {str(e)}")

# --- LAYER 2: DATA-STORES ---
def check_datastores():
    print(f"\n{Colors.BOLD}{Colors.HEADER}=== LAYER 2: DATA-STORES ==={Colors.ENDC}")
    
    # Mongo
    def t_mongo():
        uri = f"mongodb://{DATABASE_CONFIG['mongo']['user']}:{DATABASE_CONFIG['mongo']['pass']}@{DATABASE_CONFIG['mongo']['host']}:{DATABASE_CONFIG['mongo']['port']}/?authSource=admin"
        client = pymongo.MongoClient(uri, serverSelectionTimeoutMS=2000)
        client.server_info()
    
    test_with_retry("mongo", t_mongo, f"{DATABASE_CONFIG['mongo']['host']}:{DATABASE_CONFIG['mongo']['port']}")

    # Postgres
    def t_postgres():
        conn = psycopg2.connect(
            host=DATABASE_CONFIG['postgres']['host'],
            port=DATABASE_CONFIG['postgres']['port'],
            user=DATABASE_CONFIG['postgres']['user'],
            password=DATABASE_CONFIG['postgres']['pass'],
            dbname=DATABASE_CONFIG['postgres']['db'],
            connect_timeout=2
        )
        conn.close()

    test_with_retry("postgres", t_postgres, f"{DATABASE_CONFIG['postgres']['host']}:{DATABASE_CONFIG['postgres']['port']}")

    # Redis
    def t_redis():
        r = redis.Redis(
            host=DATABASE_CONFIG['redis']['host'],
            port=DATABASE_CONFIG['redis']['port'],
            password=DATABASE_CONFIG['redis']['pass'],
            socket_timeout=2
        )
        r.ping()

    test_with_retry("redis", t_redis, f"{DATABASE_CONFIG['redis']['host']}:{DATABASE_CONFIG['redis']['port']}")

    # Kafka
    def t_kafka():
        consumer = kafka_module.KafkaConsumer(
            bootstrap_servers=[f"{DATABASE_CONFIG['kafka']['host']}:{DATABASE_CONFIG['kafka']['port']}"],
            request_timeout_ms=2000,
            consumer_timeout_ms=2000
        )
        consumer.topics()

    test_with_retry("kafka", t_kafka, f"{DATABASE_CONFIG['kafka']['host']}:{DATABASE_CONFIG['kafka']['port']}")

    # InfluxDB
    def t_influx():
        url = f"http://{DATABASE_CONFIG['influx']['host']}:{DATABASE_CONFIG['influx']['port']}"
        client = influxdb_client.InfluxDBClient(url=url, token=DATABASE_CONFIG['influx']['token'], org=DATABASE_CONFIG['influx']['org'])
        health = client.health()
        if health.status != "pass":
             raise Exception(f"Status: {health.status}")
    
    test_with_retry("influx", t_influx, f"{DATABASE_CONFIG['influx']['host']}:{DATABASE_CONFIG['influx']['port']}")

    # Vault
    def t_vault():
        url = f"http://{DATABASE_CONFIG['vault']['host']}:{DATABASE_CONFIG['vault']['port']}/v1/sys/health"
        headers = {"X-Vault-Token": DATABASE_CONFIG['vault']['token']}
        r = requests.get(url, headers=headers, timeout=2)
        if r.status_code in [200, 429]:
            info = r.json()
            status_msg = f"OK ({'Unsealed' if not info.get('sealed') else 'SEALED'})"
            return status_msg
        else:
             raise Exception(f"HTTP {r.status_code}")
             
    test_with_retry("vault", t_vault, f"{DATABASE_CONFIG['vault']['host']}:{DATABASE_CONFIG['vault']['port']}")


# --- LAYER 3: MONITORING ---
def check_monitoring():
    print(f"\n{Colors.BOLD}{Colors.HEADER}=== LAYER 3: MONITORING ==={Colors.ENDC}")
    
    # Grafana
    def t_grafana():
        target = f"{DATABASE_CONFIG['grafana']['host']}:{DATABASE_CONFIG['grafana']['port']}"
        r = requests.get(f"http://{target}/api/health", timeout=2)
        if r.status_code == 200:
            return "API Responding"
        else:
            raise Exception(f"HTTP {r.status_code}")

    test_with_retry("grafana", t_grafana, f"{DATABASE_CONFIG['grafana']['host']}:{DATABASE_CONFIG['grafana']['port']}")

    # Prometheus
    def t_prom():
        target = f"{DATABASE_CONFIG['prometheus']['host']}:{DATABASE_CONFIG['prometheus']['port']}"
        url = f"http://{target}/-/healthy"
        r = requests.get(url, timeout=2)
        if r.status_code == 200:
            return "API Healthy"
        else:
            raise Exception(f"HTTP {r.status_code}")
    
    test_with_retry("prometheus", t_prom, f"{DATABASE_CONFIG['prometheus']['host']}:{DATABASE_CONFIG['prometheus']['port']}")

    # Loki
    def t_loki():
        target = f"{DATABASE_CONFIG['loki']['host']}:{DATABASE_CONFIG['loki']['port']}"
        endpoints = ["/ready", "/loki/api/v1/ready", "/metrics", "/loki/ready"]
        for ep in endpoints:
            try:
                r = requests.get(f"http://{target}{ep}", timeout=2)
                if r.status_code == 200:
                    return f"API Healthy ({ep})"
            except:
                pass
        raise Exception("Health probe failed (All endpoints 404/Timeout)")

    test_with_retry("loki", t_loki, f"{DATABASE_CONFIG['loki']['host']}:{DATABASE_CONFIG['loki']['port']}")


# --- LAYER 4: IDENTITY ---
def check_identity():
    print(f"\n{Colors.BOLD}{Colors.HEADER}=== LAYER 4: IDENTITY ==={Colors.ENDC}")
    
    def t_authentik():
        if AM_ENV == "local":
            target = f"localhost:{BRIDGE_MAP['authentik']['port']}"
            url = f"http://{target}/-/health/ready/"
        else:
            url = "https://auth.munish.org/-/health/ready/"
            
        r = requests.get(url, timeout=2, verify=False)
        if r.status_code in [200, 204]:
            return "Ready Endpoint Responding"
        else:
            raise Exception(f"HTTP {r.status_code}")

    # For local, identity might be intentionally deferred
    target_str = f"localhost:{BRIDGE_MAP['authentik']['port']}" if AM_ENV == "local" else "auth.munish.org"
    try:
        test_with_retry("authentik", t_authentik, target_str)
    except Exception:
        print_status("Authentik", "FAIL", target_str, "Unreachable (Expected if Identity is deferred)")


if __name__ == "__main__":
    print(f"\n{Colors.BOLD}{Colors.HEADER}{'='*70}{Colors.ENDC}")
    print(f"{Colors.BOLD}{Colors.OKCYAN}🚀 AM-INFRA SMART CONNECTIVITY ORCHESTRATOR{Colors.ENDC}")
    print(f"{Colors.OKCYAN}ENVIRONMENT: {CONF['name']}{Colors.ENDC}")
    print(f"{Colors.BOLD}{Colors.HEADER}{'='*70}{Colors.ENDC}\n")
    
    layer_arg = None
    for arg in sys.argv:
        if arg.startswith("--layer="):
            layer_arg = arg.split("=")[1].lower()

    if not layer_arg or layer_arg in ["foundation", "all"]:
        check_foundation()
    if not layer_arg or layer_arg in ["data-stores", "datastores", "all"]:
        check_datastores()
    if not layer_arg or layer_arg in ["monitoring", "all"]:
        check_monitoring()
    if not layer_arg or layer_arg in ["identity", "all"]:
        check_identity()
    
    print(f"\n{Colors.BOLD}{Colors.HEADER}{'='*70}{Colors.ENDC}\n")
