import json,subprocess
for ns in ["am-apps-preprod","am-agents-preprod"]:
  r=subprocess.run(["docker","exec","am-preprod-control-plane","kubectl","-n",ns,"get","secretproviderclass","-o","json","--request-timeout=60s"],capture_output=True,text=True)
  if r.returncode!=0:
    print(ns,"list fail",r.stderr[:200]); continue
  for it in (json.loads(r.stdout).get("items") or []):
    name=it["metadata"]["name"]
    params=(it.get("spec") or {}).get("parameters") or {}
    if params.get("audience")=="vault":
      print("ok",ns,name); continue
    patch=json.dumps({"spec":{"parameters":{"audience":"vault"}}})
    p=subprocess.run(["docker","exec","am-preprod-control-plane","kubectl","-n",ns,"patch","secretproviderclass",name,"--type=merge","-p",patch,"--request-timeout=60s"],capture_output=True,text=True)
    print("patch",ns,name,p.returncode,(p.stdout or p.stderr)[:160])
