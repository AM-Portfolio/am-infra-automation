import os
import paramiko
from lib.env import Env
from lib.ui import Colors, print_error

class VPSClient:
    """A reusable SSH client for executing commands on the infrastructure VPS."""

    def __init__(self):
        self.host = Env.get("VPS_HOST")
        self.user = Env.get("VPS_USER", "root")
        self.password = Env.get("VPS_PASS")
        self.client = None

    def connect(self):
        if not self.host or not self.password:
            raise ValueError("Missing VPS_HOST or VPS_PASS in .env.infra")
        
        try:
            self.client = paramiko.SSHClient()
            self.client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            self.client.connect(self.host, username=self.user, password=self.password, timeout=10)
            return True
        except Exception as e:
            print_error(f"Failed to connect to VPS: {str(e)}")
            return False

    def execute(self, command, description=None):
        """Executes a command and returns status, stdout, stderr."""
        if not self.client:
            if not self.connect():
                return -1, "", "Connection failed"

        if description:
            print(f"{Colors.BLUE}>> {description}...{Colors.ENDC}")

        stdin, stdout, stderr = self.client.exec_command(command)
        exit_status = stdout.channel.recv_exit_status()
        out_str = stdout.read().decode().strip()
        err_str = stderr.read().decode().strip()

        return exit_status, out_str, err_str

    def push(self, local_path, remote_path):
        """Pushes a file or directory to the VPS via SFTP."""
        if not self.client:
            if not self.connect():
                return False

        try:
            sftp = self.client.open_sftp()
            
            def mkdir_p(remote_directory):
                """Recursively creates a remote directory."""
                if remote_directory == "/" or not remote_directory:
                    return
                try:
                    sftp.stat(remote_directory)
                except (IOError, FileNotFoundError):
                    mkdir_p(os.path.dirname(remote_directory.rstrip("/")))
                    try:
                        sftp.mkdir(remote_directory)
                    except IOError:
                        pass # Might already exist from parallel race

            if not os.path.exists(local_path):
                print_error(f"Local source does not exist: {local_path}")
                return False

            if os.path.isfile(local_path):
                mkdir_p(os.path.dirname(remote_path))
                sftp.put(local_path, remote_path)
            else:
                # Directory push
                mkdir_p(remote_path)
                for root, dirs, files in os.walk(local_path):
                    for file in files:
                        local_file = os.path.join(root, file)
                        rel_path = os.path.relpath(local_file, local_path)
                        remote_file = os.path.join(remote_path, rel_path).replace("\\", "/")
                        
                        # Ensure parent dir exists for this file
                        mkdir_p(os.path.dirname(remote_file))
                        try:
                            sftp.put(local_file, remote_file)
                        except Exception as e:
                            print_error(f"Failed to push {local_file} -> {remote_file}: {str(e)}")
                            raise e
            
            sftp.close()
            return True
        except Exception as e:
            print_error(f"Failed to push files from {local_path} to {remote_path}: {str(e)}")
            return False

    def close(self):
        if self.client:
            self.client.close()
            self.client = None

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
