from lib.vps import VPSClient
vps = VPSClient()
if vps.connect():
    print("--- TAILSCALE ADDR ---")
    status, stdout, _ = vps.execute("ip addr show tailscale0", "Checking IP")
    print(stdout)
    
    print("\n--- NETSTAT (LISTENING) ---")
    status, stdout, _ = vps.execute("netstat -tuln", "Checking Bindings")
    print(stdout)
    
    print("\n--- UFW STATUS ---")
    status, stdout, _ = vps.execute("ufw status", "Checking Firewall")
    print(stdout)
vps.disconnect()
