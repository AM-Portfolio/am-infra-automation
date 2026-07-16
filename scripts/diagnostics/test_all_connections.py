import sys
import subprocess
import os
import socket

# Environment Host configuration
INFRA_HOST = os.environ.get("INFRA_HOST", "localhost")
print(f"🌐 Using INFRA_HOST: {INFRA_HOST}")

# Hijack socket for kafka-headless local wrapper setup (if needed)
orig_getaddrinfo = socket.getaddrinfo
def custom_getaddrinfo(*args, **kwargs):
    host = args[0] if args else ""
    port = args[1] if len(args) > 1 else 0
    
    # ANY Kafka connection intent (Port 9092) should be routed to local port forward bridge
    if port == 9092:
        return orig_getaddrinfo(INFRA_HOST, *args[1:], **kwargs)
    return orig_getaddrinfo(*args, **kwargs)
socket.getaddrinfo = custom_getaddrinfo

# Path setup
workspace_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
credentials_path = os.path.join(workspace_root, "generated-credentials.txt")

def load_credentials():
    """Load credentials from generated-credentials.txt."""
    creds = {}
    if not os.path.exists(credentials_path):
        print(f"❌ Error: Credentials file not found at {credentials_path}")
        return creds
        
    with open(credentials_path) as f:
        for line in f:
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                creds[k.strip()] = v.strip()
    return creds

def lazy_import(package_name, install_name=None):
    """Dynamically imports a package, installing it if missing."""
    install_name = install_name or package_name
    try:
        return __import__(package_name)
    except ImportError:
        print(f"Installing missing dependency: {install_name}...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", install_name])
        return __import__(package_name)

def test_mongo(creds):
    print("\n--- 🍃 Testing MongoDB ---")
    try:
        pymongo = lazy_import("pymongo")
        username = creds.get("MONGODB_USERNAME")
        password = creds.get("MONGODB_PASSWORD")
        
        # Test connection
        client = pymongo.MongoClient(
            host=INFRA_HOST,
            port=27017,
            username=username,
            password=password,
            authSource="admin",
            serverSelectionTimeoutMS=5000
        )
        client.server_info() # Trigger connection check
        print("✅ MongoDB Connection Successful!")
        print(f"Databases: {client.list_database_names()}")
        client.close()
        return True
    except Exception as e:
        print(f"❌ MongoDB Failed: {e}")
        return False

def test_postgres(creds):
    print("\n--- 🐘 Testing PostgreSQL ---")
    try:
        psycopg2 = lazy_import("psycopg2", "psycopg2-binary")
        username = creds.get("POSTGRESQL_USERNAME", "postgres")
        password = creds.get("POSTGRESQL_PASSWORD")
        
        conn = psycopg2.connect(
            host=INFRA_HOST,
            port=5432,
            database="portfolio",
            user=username,
            password=password,
            connect_timeout=5
        )
        cur = conn.cursor()
        cur.execute("SELECT 1;")
        cur.fetchone()
        cur.close()
        conn.close()
        print("✅ PostgreSQL Connection Successful!")
        return True
    except Exception as e:
        print(f"❌ PostgreSQL Failed: {e}")
        return False

def test_redis(creds):
    print("\n--- 🔴 Testing Redis ---")
    try:
        redis = lazy_import("redis")
        password = creds.get("REDIS_PASSWORD")
        
        r = redis.Redis(
            host=INFRA_HOST,
            port=6379,
            password=password,
            socket_timeout=5
        )
        r.ping()
        print("✅ Redis Connection Successful!")
        r.close()
        return True
    except Exception as e:
        print(f"❌ Redis Failed: {e}")
        return False

def test_influx(creds):
    print("\n--- 📈 Testing InfluxDB ---")
    try:
        influxdb_client = lazy_import("influxdb_client")
        token = creds.get("INFLUXDB_TOKEN")
        org = creds.get("INFLUXDB_ORG", "am-portfolio")
        
        client = influxdb_client.InfluxDBClient(
            url=f"http://{INFRA_HOST}:8086",
            token=token,
            org=org,
            timeout=5000
        )
        # InfluxDBClient has a health() method
        health = client.health()
        if health.status == "pass":
            print("✅ InfluxDB Connection Successful!")
            client.close()
            return True
        else:
            print(f"❌ InfluxDB Unhealthy: {health.message}")
            client.close()
            return False
    except Exception as e:
        print(f"❌ InfluxDB Failed: {e}")
        return False

def test_kafka(creds):
    print("\n--- 🚢 Testing Kafka ---")
    try:
        kafka = lazy_import("kafka", "kafka-python")
        username = creds.get("KAFKA_USERNAME")
        password = creds.get("KAFKA_PASSWORD")
        bootstrap_servers = "kafka-headless:9092"
        
        admin_client = kafka.KafkaAdminClient(
            bootstrap_servers=bootstrap_servers,
            security_protocol='SASL_PLAINTEXT',
            sasl_mechanism='SCRAM-SHA-256',
            sasl_plain_username=username,
            sasl_plain_password=password,
            api_version=(2, 8, 1),
            request_timeout_ms=5000
        )
        topics = admin_client.list_topics()
        admin_client.close()
        print("✅ Kafka Connection Successful!")
        print(f"Topics: {topics}")
        return True
    except Exception as e:
        import traceback
        traceback.print_exc()
        print(f"❌ Kafka Failed: {e}")
        return False

def main():
    creds = load_credentials()
    if not creds:
        return

    # Map aliases to tests
    test_map = {
        "mongo": test_mongo,
        "postgres": test_postgres,
        "postgresql": test_postgres,
        "redis": test_redis,
        "influx": test_influx,
        "influxdb": test_influx,
        "kafka": test_kafka
    }

    target = sys.argv[1].lower() if len(sys.argv) > 1 else "all"

    print(f"🚀 Starting Connectivity Tests (Target: {target})")
    print(f"💡 Reading credentials from: {credentials_path}")

    results = {}
    if target == "all":
        for name, test_func in test_map.items():
            # Run Postgresql only once
            if name == "postgresql": continue
            results[name] = test_func(creds)
    elif target in test_map:
        results[target] = test_map[target](creds)
    else:
        print(f"❌ Unknown target '{target}'. Available: {', '.join(test_map.keys())}")
        return

    print("\n--- 📊 Summary ---")
    all_passed = True
    for name, success in results.items():
        status = "✅ PASSED" if success else "❌ FAILED"
        print(f"{name.capitalize()}: {status}")
        if not success:
            all_passed = False
            
    print("\n🎉 Total Result: " + ("✅ SUCCESS" if all_passed else "❌ FAILURES FOUND"))

if __name__ == "__main__":
    main()
