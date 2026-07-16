import os
import shutil
import re
from datetime import datetime
import json

# --- Configuration ---
# --- Path Bootstrapping ---
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(os.path.dirname(SCRIPT_DIR))
SCRIPTS_DIR = os.path.join(ROOT_DIR, "scripts")

# Add cross-package directories to path
import sys
sys.path.append(os.path.join(SCRIPTS_DIR, "shared"))

SECRETS_DIR = os.path.join(ROOT_DIR, "infrastructure-secrets")
LATEST_DIR = os.path.join(SECRETS_DIR, "latest")
BACKUPS_DIR = os.path.join(SECRETS_DIR, "backups")
CREDENTIALS_FILE = os.path.join(LATEST_DIR, "credentials.txt")
TERRAFORM_RAW_FILE = os.path.join(LATEST_DIR, "terraform-raw.json")
OLD_CREDENTIALS_FILE = os.path.join(ROOT_DIR, "generated-credentials.txt")

# Helper for colorful console output
class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BOLD = '\033[1m'
    ENDC = '\033[0m'

def get_timestamp():
    return datetime.now().isoformat()

def ensure_dirs():
    for d in [LATEST_DIR, BACKUPS_DIR]:
        if not os.path.exists(d):
            os.makedirs(d)

def parse_existing_pretty():
    """Parses the existing pretty credentials.txt to preserve service-level timestamps."""
    creds = {}
    timestamps = {}
    if not os.path.exists(CREDENTIALS_FILE):
        return creds, timestamps
    
    current_service = None
    with open(CREDENTIALS_FILE, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith("# ---"):
                service_match = re.search(r"# --- ([\w\s\-\(\)]+)", line)
                if service_match:
                    current_service = service_match.group(1).strip().upper()
                    creds[current_service] = {}
            elif line.startswith("# Updated At:") and current_service:
                ts_match = re.search(r"# Updated At:\s*(.+)", line)
                if ts_match:
                    timestamps[current_service] = ts_match.group(1).strip()
            elif "=" in line and current_service:
                k, v = line.split("=", 1)
                creds[current_service][k.strip()] = v.strip()
    return creds, timestamps

def parse_kv(file_path):
    creds = {}
    if not os.path.exists(file_path):
        return creds
    current_service = "General"
    with open(file_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            if line.startswith("#"):
                service_match = re.search(r"#\s*([\w\s\-\(\)]+)", line)
                if service_match:
                    candidate = service_match.group(1).strip()
                    if candidate and not any(x in candidate.lower() for x in ["generated", "terraform", "====="]):
                        current_service = candidate.upper()
                continue
            if "=" in line:
                key, val = line.split("=", 1)
                if current_service not in creds:
                    creds[current_service] = {}
                creds[current_service][key.strip()] = val.strip()
    return creds

def backup_current():
    if os.path.exists(CREDENTIALS_FILE):
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_path = os.path.join(BACKUPS_DIR, f"credentials_{ts}.txt")
        shutil.copy2(CREDENTIALS_FILE, backup_path)
        print(f"{Colors.YELLOW}[BACKUP]{Colors.ENDC} Created: {os.path.basename(backup_path)}")

def write_pretty(new_creds, force_new_ts=False):
    ensure_dirs()
    existing_creds, existing_ts = parse_existing_pretty()
    
    global_ts = get_timestamp()
    has_changes = False
    
    # Check for changes and update timestamps
    final_ts = {}
    for service, pairs in new_creds.items():
        old_pairs = existing_creds.get(service, {})
        if pairs != old_pairs or force_new_ts:
            final_ts[service] = global_ts
            has_changes = True
        else:
            final_ts[service] = existing_ts.get(service, global_ts)

    if not has_changes and os.path.exists(CREDENTIALS_FILE):
        print(f"{Colors.CYAN}[SYNC]{Colors.ENDC} No changes detected. Skipping update.")
        return

    backup_current()
    
    with open(CREDENTIALS_FILE, 'w') as f:
        f.write("# " + "="*76 + "\n")
        f.write("# INFRASTRUCTURE SECRETS (VERSIONED & SECURE)\n")
        f.write(f"# Global Last Sync: {global_ts}\n")
        f.write("# " + "="*76 + "\n\n")

        for service, pairs in sorted(new_creds.items()):
            f.write(f"# --- {service} " + "-"*(70 - len(service)) + "\n")
            f.write(f"# Updated At: {final_ts.get(service, global_ts)}\n")
            for k, v in sorted(pairs.items()):
                f.write(f"{k}={v}\n")
            f.write("\n")
    
    print(f"{Colors.GREEN}[SUCCESS]{Colors.ENDC} Updated: {CREDENTIALS_FILE}")

def sync_terraform():
    if not os.path.exists(TERRAFORM_RAW_FILE):
        print(f"{Colors.RED}[ERROR]{Colors.ENDC} terraform-raw.json not found. Run terraform apply first.")
        return

    print(f"{Colors.CYAN}[SYNC]{Colors.ENDC} Synchronizing with Terraform state...")
    with open(TERRAFORM_RAW_FILE, 'r') as f:
        new_creds = json.load(f)
    
    write_pretty(new_creds)

def view_secrets():
    if not os.path.exists(CREDENTIALS_FILE):
        print(f"{Colors.RED}No credentials file found.{Colors.ENDC}")
        return

    print(f"\n{Colors.BOLD}{Colors.HEADER}{'='*80}{Colors.ENDC}")
    print(f"{Colors.BOLD}{Colors.CYAN}INFRASTRUCTURE SECRETS VIEWER{Colors.ENDC}")
    print(f"{Colors.BOLD}{Colors.HEADER}{'='*80}{Colors.ENDC}\n")

    with open(CREDENTIALS_FILE, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith("# ---"):
                print(f"\n{Colors.BOLD}{Colors.BLUE}{line}{Colors.ENDC}")
            elif line.startswith("# Updated At:"):
                print(f"{Colors.YELLOW}{line}{Colors.ENDC}")
            elif "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                print(f"{Colors.GREEN}{k.ljust(25)}{Colors.ENDC} : {v}")
    print(f"\n{Colors.BOLD}{Colors.HEADER}{'='*80}{Colors.ENDC}\n")

if __name__ == "__main__":
    import sys
    ensure_dirs()
    
    if "--view" in sys.argv:
        view_secrets()
    elif "--migrate" in sys.argv:
        print(f"{Colors.CYAN}[MIGRATE]{Colors.ENDC} importing existing credentials...")
        existing = parse_kv(OLD_CREDENTIALS_FILE)
        if existing:
            write_pretty(existing, force_new_ts=True)
        else:
            print(f"{Colors.RED}Source file not found: {OLD_CREDENTIALS_FILE}{Colors.ENDC}")
    elif "--sync" in sys.argv:
        sync_terraform()
    else:
        print("Usage: python manage_secrets.py [--migrate | --view | --sync]")
