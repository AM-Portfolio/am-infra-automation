import sys
import os

# --- Path Bootstrapping ---
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(os.path.dirname(SCRIPT_DIR))

def main():
    # Look for keys in the repository root
    keys_file = os.path.join(ROOT_DIR, "vault-keys-final.json")
    if not os.path.exists(keys_file):
        keys_file = os.path.join(ROOT_DIR, "vault-keys.json")
    
    # Also check current directory for vault-keys.json
    if not os.path.exists(keys_file):
        keys_file = os.path.abspath("vault-keys.json")
        
    success = ensure_vault_unsealed(keys_file_path=keys_file)
    if success:
        print("Vault unseal process completed successfully.")
        sys.exit(0)
    else:
        print("Vault unseal process failed.")
        sys.exit(1)

if __name__ == "__main__":
    main()
