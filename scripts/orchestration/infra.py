import argparse
import os
import sys

# --- Path Bootstrapping ---
# Get the absolute path of the repository root
script_dir = os.path.dirname(os.path.abspath(__file__))
root_dir = os.path.dirname(os.path.dirname(script_dir))
scripts_dir = os.path.join(root_dir, "scripts")

# Add shared/lib and other packages to path
sys.path.append(os.path.join(scripts_dir, "shared"))
sys.path.append(os.path.join(scripts_dir, "security"))
sys.path.append(os.path.join(scripts_dir, "diagnostics"))
sys.path.append(os.path.join(scripts_dir, "networking"))

from lib.env import Env
from lib.ui import Colors, print_header, print_success, print_error
from lib.vps import VPSClient
from lib.logger import log_infra, log_tunnel, log_secrets, log_terraform

# --- Command Handlers ---

def handle_sync(args):
    """Syncs infrastructure secrets with Terraform state."""
    log_secrets("Starting infrastructure secrets sync")
    print_header("INFRASTRUCTURE SECRETS SYNC")
    
    # Import locally to avoid circular dependencies if any
    sys.path.append(os.path.dirname(os.path.abspath(__file__)))
    import manage_secrets
    manage_secrets.sync_terraform()
    print_success("Secrets synchronization complete.")

def handle_verify(args):
    """Verifies connectivity to infrastructure services."""
    env_target = args.env or "vps-tunnel"
    log_infra(f"Starting connectivity verification for env: {env_target}")
    print_header(f"CONNECTIVITY VERIFICATION ({env_target.upper()})")
    
    # Set environment variable for check_connectivity.py logic
    os.environ["AM_ENV"] = env_target
    
    sys.path.append(os.path.dirname(os.path.abspath(__file__)))
    import check_connectivity
    
    # Run all checks (using the module-level functions)
    check_connectivity.check_mongo()
    check_connectivity.check_postgres()
    check_connectivity.check_redis()
    check_connectivity.check_kafka()
    check_connectivity.check_influx()
    check_connectivity.check_vault()
    check_connectivity.check_traefik()
    
    print_success("Connectivity verification complete.")

def handle_tunnel(args):
    """Manages the Cloudflare Tunnel."""
    if args.action == "deploy":
        log_tunnel("Starting Cloudflare Tunnel deployment")
        sys.path.append(os.path.dirname(os.path.abspath(__file__)))
        import deploy_tunnel # This will run its main logic
        print_success("Tunnel deployment task triggered.")
        
    elif args.action == "status":
        log_tunnel("Checking Cloudflare Tunnel status")
        sys.path.append(os.path.dirname(os.path.abspath(__file__)))
        import verify_tunnel # This will run its main logic
        print_success("Status check complete.")

    elif args.action == "logs":
        log_tunnel(f"Fetching tunnel logs (local={args.local})")
        if args.local:
            print(f"{Colors.CYAN}Fetching local cloudflared logs...{Colors.ENDC}")
            os.system("docker logs cloudflared-tunnel")
        else:
            print_header("REMOTE CLOUDFLARE TUNNEL LOGS (VPS)")
            with VPSClient() as vps:
                if vps.connect():
                    # Get last 100 lines
                    cmd = "docker logs --tail 100 cloudflared-tunnel"
                    status, stdout, stderr = vps.execute(cmd, "Fetching logs from VPS")
                    if status == 0:
                        print(stdout)
                        if not stdout:
                            print(f"{Colors.YELLOW}No logs found or container is empty.{Colors.ENDC}")
                    else:
                        print_error(f"Failed to fetch logs: {stderr}")
                else:
                    print_error("Could not connect to VPS to fetch logs.")
                
def handle_exec(args):
    """Executes a command on the VPS."""
    print_header(f"REMOTE EXECUTION")
    # Join list of arguments into a single command string
    full_cmd = " ".join(args.cmd)
    with VPSClient() as vps:
        if vps.connect():
            status, stdout, stderr = vps.execute(full_cmd, "Running remote command")
            if status == 0:
                if stdout: print(stdout)
            else:
                if stderr: print_error(stderr)
                sys.exit(status)
        else:
            print_error("Could not connect to VPS.")
            sys.exit(1)

def handle_push(args):
    """Pushes a file or directory to the VPS."""
    print_header(f"REMOTE PUSH")
    with VPSClient() as vps:
        if vps.connect():
            success = vps.push(args.src, args.dest)
            if success:
                print_success(f"Successfully pushed {args.src} to {args.dest}")
            else:
                print_error(f"Failed to push {args.src}")
                sys.exit(1)
        else:
            print_error("Could not connect to VPS.")
            sys.exit(1)

def handle_vault(args):
    """Manages Vault unsealing and status."""
    import json
    import subprocess
    print_header(f"VAULT {args.action.upper()}")
    
    # root_dir is already bootstrapped at the top
    keys_file = os.path.join(root_dir, "vault-keys-final.json")
    
    if args.action == "unseal":
        if not os.path.exists(keys_file):
            print_error(f"Vault keys not found at {keys_file}.")
            sys.exit(1)
            
        try:
            with open(keys_file, 'r', encoding='utf-8') as f:
                content = f.read().strip()
                if not content:
                    raise ValueError("File is empty")
                keys = json.loads(content)
        except Exception as e:
            print_error(f"Failed to read/parse Vault keys: {str(e)}")
            sys.exit(1)
            
        unseal_keys = keys.get("unseal_keys_hex", [])
        if not unseal_keys:
            print_error("No unseal key found in keys file.")
            sys.exit(1)
            
        unseal_key = unseal_keys[0]
        
        print(f"{Colors.CYAN}Unsealing Vault on {args.env}...{Colors.ENDC}")
        
        # Standardized pathing based on environment
        config_file = "kubeconfig.vps" if args.env == "hostbet-vps" else "kubeconfig.local"
        context_name = "kind-am-preprod" if args.env == "hostbet-vps" else "kind-am-local"

        kube_cmd = [
            "kubectl", "--kubeconfig", os.path.join(root_dir, "k8s", config_file), "--context", context_name,
            "exec", "vault-0", "-n", "vault", "--", "vault", "operator", "unseal", unseal_key
        ]

        
        result = subprocess.run(kube_cmd, cwd=root_dir)
        if result.returncode == 0:
            print_success("Vault unsealed successfully.")
        else:
            print_error("Vault unseal failed.")
            sys.exit(result.returncode)

def handle_terraform(args):
    """Wraps Terraform commands with secure variable injection and logging."""
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
    import subprocess
    
    print_header(f"TERRAFORM {args.action.upper()} - LAYER: {args.layer}")
    log_terraform(f"Starting terraform {args.action} on layer {args.layer} with env {args.env}")
    
    # root_dir is already bootstrapped
    base_layer_dir = os.path.join(root_dir, "terraform", args.layer)
    
    # Smart Directory Resolution: check for environment-specific subdirectory
    tf_dir = base_layer_dir
    env_sub_dir = os.path.join(base_layer_dir, args.env)
    
    # If the env is 'local' or 'vps', and there's a matching folder, use it as CWD
    if os.path.exists(env_sub_dir) and os.path.isdir(env_sub_dir):
        tf_dir = env_sub_dir
    # Handle the 'hostbet-vps' -> 'vps' alias if it exists
    elif args.env == "hostbet-vps":
        vps_dir = os.path.join(base_layer_dir, "vps")
        if os.path.exists(vps_dir) and os.path.isdir(vps_dir):
            tf_dir = vps_dir
    env_vars = os.environ.copy()
    
    # Inject variables from Env
    config = Env.get_config()
    if config:
        for k, v in config.items():
            if k:
                env_vars[f"TF_VAR_{k.lower()}"] = str(v)
            
    # Also explicitly ensure these critical ones are injected
    env_vars["TF_VAR_github_pat"] = Env.get("GITHUB_PAT", "")
    env_vars["TF_VAR_github_repo_url"] = Env.get("REPO_URL", "https://github.com/AM-Portfolio")
    env_vars["TF_VAR_vps_host"] = Env.get("VPS_HOST", "203.174.22.129")
    env_vars["TF_VAR_vps_user"] = Env.get("VPS_USER", "root")
    env_vars["TF_VAR_vps_pass"] = Env.get("VPS_PASS", "")

    # Default empty strings for DB password overrides to prevent Terraform errors
    env_vars["TF_VAR_mongodb_password"]    = Env.get("MONGO_PASSWORD", "")
    env_vars["TF_VAR_postgresql_password"] = Env.get("POSTGRES_PASSWORD", "")
    env_vars["TF_VAR_redis_password"]      = Env.get("REDIS_PASSWORD", "")
    env_vars["TF_VAR_kafka_password"]      = Env.get("KAFKA_PASSWORD", "")
    env_vars["TF_VAR_influxdb_password"]   = Env.get("INFLUXDB_PASSWORD", "")
    env_vars["TF_VAR_grafana_password"]    = Env.get("GRAFANA_PASSWORD", "")
    
    # Universal Tokens
    env_vars["TF_VAR_cloudflare_token"]    = Env.get("CLOUDFLARED_TOKEN", "")
    env_vars["TF_VAR_influxdb_token"]      = Env.get("INFLUXDB_TOKEN", "")

    # Use local terraform.exe if it exists
    tf_exe = os.path.join(root_dir, "terraform", "terraform.exe")
    if not os.path.exists(tf_exe):
        tf_exe = "terraform" # fallback to system terraform
        
    if args.action == "destroy":
        print(f"\n{Colors.FAIL}! WARNING ! WARNING ! WARNING !{Colors.ENDC}")
        confirmation = input(f"{Colors.FAIL}You are about to DESTROY the '{args.layer}' layer! Type 'confirm-destroy-{args.layer}' to proceed: {Colors.ENDC}")
        if confirmation != f"confirm-destroy-{args.layer}":
            print_error("Destroy cancelled. Safety lock enforced.")
            sys.exit(1)

    cmd = [tf_exe, args.action]
    if args.action in ["apply", "destroy"]:
        cmd.append("-auto-approve")
        
    if args.action in ["plan", "apply", "destroy"]:
        # Universal Kubeconfig Standard
        config_file = "kubeconfig.vps" if args.env == "hostbet-vps" else "kubeconfig.local"
        context_name = "kind-am-preprod" if args.env == "hostbet-vps" else "kind-am-local"

        cmd.extend([
            "-var", f"environment={args.env}",
            "-var", f"kubeconfig_path=../../../k8s/{config_file}",
            "-var", f"kubeconfig_context={context_name}"
        ])
        
    log_terraform(f"Executing: {' '.join(cmd)} in {tf_dir}")
    print(f"{Colors.CYAN}Running in {args.layer}...{Colors.ENDC}")
    
    # Run the process and pipe output so both console and logger see it.
    process = subprocess.Popen(cmd, cwd=tf_dir, env=env_vars, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    
    for line in iter(process.stdout.readline, ''):
        sys.stdout.write(line)
        sys.stdout.flush()
        log_terraform(line.strip())
        
    process.wait()
    
    if process.returncode == 0:
        print_success(f"Terraform {args.action} on {args.layer} finished successfully.")
        log_terraform(f"Finished {args.action} on {args.layer} with SUCCESS")
    else:
        print_error(f"Terraform {args.action} failed with exit code {process.returncode}")
        log_terraform(f"Finished {args.action} on {args.layer} with ERROR (code {process.returncode})", level="error")
        sys.exit(process.returncode)

def main():
    # Parent parser for shared arguments like --env
    parent_parser = argparse.ArgumentParser(add_help=False)
    parent_parser.add_argument("--env", choices=["local", "hostbet-vps"], help="Target environment")

    parser = argparse.ArgumentParser(description="Am-Infra Unified CLI")
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # Sync
    subparsers.add_parser("sync", parents=[parent_parser], help="Synchronize secrets from Terraform")
    
    # Verify
    subparsers.add_parser("verify", parents=[parent_parser], help="Verify service connectivity")
    
    # Tunnel
    tunnel_cmd = subparsers.add_parser("tunnel", parents=[parent_parser], help="Manage Cloudflare Tunnel")
    tunnel_sub = tunnel_cmd.add_subparsers(dest="action", help="Tunnel actions")
    
    # Tunnel Actions
    tunnel_sub.add_parser("deploy", parents=[parent_parser], help="Deploy tunnel to VPS")
    tunnel_sub.add_parser("status", parents=[parent_parser], help="Check tunnel status on VPS")
    
    log_parser = tunnel_sub.add_parser("logs", parents=[parent_parser], help="Show tunnel logs")
    log_parser.add_argument("--local", action="store_true", help="Show local logs instead of VPS")
    
    # Exec
    exec_cmd = subparsers.add_parser("exec", parents=[parent_parser], help="Execute a command on the VPS")
    exec_cmd.add_argument("cmd", nargs="+", help="Command to execute")

    # Push
    push_cmd = subparsers.add_parser("push", parents=[parent_parser], help="Push a file or directory to the VPS")
    push_cmd.add_argument("src", help="Source path (local)")
    push_cmd.add_argument("dest", help="Destination path (remote)")

    # Terraform (tf)
    tf_cmd = subparsers.add_parser("tf", parents=[parent_parser], help="Execute terraform layer actions")
    tf_cmd.add_argument("action", choices=["plan", "apply", "destroy", "init", "output"], help="Terraform command")
    tf_cmd.add_argument("--layer", required=True, help="Layer directory to run (e.g., core, security)")

    # Vault
    vault_cmd = subparsers.add_parser("vault", parents=[parent_parser], help="Manage Vault (unseal, init)")
    vault_cmd.add_subparsers(dest="action", help="Vault actions").add_parser("unseal", parents=[parent_parser], help="Unseal Vault on VPS")

    args = parser.parse_args()

    if args.command == "sync":
        handle_sync(args)
    elif args.command == "verify":
        handle_verify(args)
    elif args.command == "tunnel":
        if args.action:
            handle_tunnel(args)
        else:
            print("Usage: infra.py tunnel [deploy|status|logs]")
    elif args.command == "exec":
        handle_exec(args)
    elif args.command == "push":
        handle_push(args)
    elif args.command == "tf":
        handle_terraform(args)
    elif args.command == "vault":
        handle_vault(args)
    else:
        parser.print_help()

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nAborted by user.")
        sys.exit(0)
