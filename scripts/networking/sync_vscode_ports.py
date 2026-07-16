import os
import sys
import json

# --- Bootstrap am-scripts ---
script_dir = os.path.dirname(os.path.abspath(__file__))
repo_root = os.path.dirname(script_dir)
am_repos_root = os.path.dirname(repo_root)
am_scripts_src = os.path.join(am_repos_root, "am-scripts", "src")

if os.path.exists(am_scripts_src):
    if am_scripts_src not in sys.path:
        sys.path.insert(0, am_scripts_src)
else:
    print(f"Error: am-scripts repository not found at {am_scripts_src}")
    sys.exit(1)

from am_scripts.utils import parse_env, setup_logger
from am_scripts.infra import get_default_service_map

logger = setup_logger("AM_VSCode_Sync")

def main():
    env_file = os.path.join(repo_root, ".env.infra")
    devcontainer_json = os.path.join(am_repos_root, ".devcontainer", "devcontainer.json")

    if not os.path.exists(env_file):
        logger.error(f"Environment file not found: {env_file}")
        sys.exit(1)

    if not os.path.exists(devcontainer_json):
        logger.error(f"devcontainer.json not found: {devcontainer_json}")
        sys.exit(1)

    # Load env
    env_config = parse_env(env_file)
    service_map = get_default_service_map()

    # Calculate ports to forward
    ports_to_forward = []
    for service, spec in service_map.items():
        # Get local port using same logic as expose_services
        # Use spec['remote'] as fallback if env var is missing or invalid
        env_var = spec.get('env')
        if env_var and env_config.get(env_var):
            try:
                local_port = int(env_config.get(env_var))
                ports_to_forward.append(local_port)
            except ValueError:
                logger.warning(f"Invalid port value for {env_var}: {env_config.get(env_var)}")
        else:
            # Fallback to remote port if env var not defined
            ports_to_forward.append(int(spec['remote']))

    # Sort and remove duplicates
    ports_to_forward = sorted(list(set(ports_to_forward)))

    # Read devcontainer.json
    try:
        with open(devcontainer_json, 'r') as f:
            data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to parse devcontainer.json: {e}")
        sys.exit(1)

    # Update forwardPorts
    data["forwardPorts"] = ports_to_forward

    # Write back
    try:
        with open(devcontainer_json, 'w') as f:
            json.dump(data, f, indent=4)
        logger.info(f"Updated {devcontainer_json} with {len(ports_to_forward)} ports.")
        print(f"Successfully synced ports in devcontainer.json: {ports_to_forward}")
    except Exception as e:
        logger.error(f"Failed to write devcontainer.json: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
