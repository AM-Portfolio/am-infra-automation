import sys
import subprocess
import os

# --- Path Bootstrapping ---
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
workspace_root = os.path.dirname(os.path.dirname(SCRIPT_DIR))
terraform_dir = os.path.join(workspace_root, "terraform")

def run_cmd(cmd):
    print(f"🚀 Running: {' '.join(cmd)} ...")
    try:
        # Run in bash directly so terraform is picked up from PATH natively
        is_windows = os.name == "nt"
        result = subprocess.run(cmd, cwd=terraform_dir, shell=is_windows)
        return result.returncode == 0
    except Exception as e:
        print(f"❌ Failed to run command: {e}")
        return False

def main():
    if len(sys.argv) < 2:
        print("\n🛠️  Terraform Wrapper for Infra")
        print("Usage: poetry run infra [init | plan | apply | destroy]")
        sys.exit(1)
        
    action = sys.argv[1].lower()
    
    if action == "init":
        run_cmd(["terraform", "init"])
    elif action == "plan":
        run_cmd(["terraform", "plan"])
    elif action == "apply":
        # Pass -auto-approve for quick use, or manual if needed
        # We can pass through any extra kwargs
        cmd_args = ["terraform", "apply"]
        if "-auto-approve" not in sys.argv:
            print("💡 Tip: append -auto-approve to skip confirmations")
        cmd_args += sys.argv[2:] # Append extra flags
        run_cmd(cmd_args)
    elif action == "destroy":
        cmd_args = ["terraform", "destroy"]
        cmd_args += sys.argv[2:]
        run_cmd(cmd_args)
    else:
        print(f"❌ Unknown command: {action}")
        print("Available actions: init, plan, apply, destroy")

if __name__ == "__main__":
    main()
