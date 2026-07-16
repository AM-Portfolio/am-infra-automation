import paramiko
import sys

# VPS Credentials
HOST = "203.174.22.129"
USER = "root"
PASSWORD = "@A1srax"

def run_ssh_commands():
    try:
        print(f"Connecting to {HOST}...")
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(HOST, username=USER, password=PASSWORD)
        
        # We ensure a socat bridge exists from Host Port 80 to Kind NodePort 30080
        # This supports direct Public IP and Tailscale IP access without local port-forward.
        commands = [
            "pkill -f 'socat TCP-LISTEN:80' || true",
            "nohup socat TCP-LISTEN:80,fork,reuseaddr TCP:172.18.0.4:30080 > /dev/null 2>&1 &",
            "netstat -tulpn | grep :80 || true"
        ]

        for cmd in commands:
            print(f"Executing: {cmd}")
            stdin, stdout, stderr = ssh.exec_command(cmd)
            stdout.channel.recv_exit_status()
            out = stdout.read().decode().strip()
            if out: print(out)

        ssh.close()
        print("✅ VPS Host Bridge (Port 80 -> Kind 30080) is active!")

    except Exception as e:
        print(f"❌ Connection error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    run_ssh_commands()
