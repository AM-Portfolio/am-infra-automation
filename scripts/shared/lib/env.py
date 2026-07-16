import os
from dotenv import dotenv_values

class Env:
    """Helper class to load and access infrastructure environment variables."""
    
    _config = None
    
    @classmethod
    def get_config(cls):
        if cls._config is None:
            # Look for .env.infra in the project root
            # Assuming scripts/lib/env.py structure
            root_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
            env_file = os.path.join(root_dir, ".env.infra")
            
            if not os.path.exists(env_file):
                 # Fallback to current dir or parent if not found exactly there
                 env_file = os.path.join(os.getcwd(), ".env.infra")
            
            cls._config = dotenv_values(env_file)
        return cls._config

    @classmethod
    def get(cls, key, default=None):
        return cls.get_config().get(key, default)

    @property
    def vps_host(self): return self.get("VPS_HOST")
    
    @property
    def vps_user(self): return self.get("VPS_USER", "root")
    
    @property
    def vps_pass(self): return self.get("VPS_PASS")
    
    @property
    def cloudflared_token(self): return self.get("CLOUDFLARED_TOKEN")
