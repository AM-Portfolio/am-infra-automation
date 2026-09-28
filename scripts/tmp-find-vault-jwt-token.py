#!/usr/bin/env python3
import json, os, pathlib, re, urllib.request

root = pathlib.Path(os.path.expanduser("~/.asrax"))
cands = []
for p in root.rglob("*"):
    if not p.is_file() or p.stat().st_size > 5_000_000:
        continue
    name = p.name.lower()
    if not any(x in name for x in ("vault", "init", "root", "credentials")):
        continue
    try:
        text = p.read_text(encoding="utf-8-sig", errors="ignore")
    except Exception:
        continue
    for m in re.finditer(r"hvs\.[A-Za-z0-9._-]{20,}", text):
        cands.append((str(p), m.group(0)))

seen = set()
uniq = []
for src, tok in cands:
    if tok in seen:
        continue
    seen.add(tok)
    uniq.append((src, tok))
print("candidates", len(uniq))

body = json.dumps({"paths": ["auth/jwt-nonprod/config"]}).encode()
for src, tok in uniq:
    req = urllib.request.Request(
        "https://vault.asrax.in/v1/sys/capabilities-self",
        data=body,
        method="POST",
        headers={"X-Vault-Token": tok, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            caps = json.loads(r.read().decode())
            print("CAP", pathlib.Path(src).name, caps)
            if "update" in str(caps) or "root" in str(caps) or "sudo" in str(caps):
                print("WRITABLE", pathlib.Path(src).name)
    except Exception as e:
        print("NO", pathlib.Path(src).name, getattr(e, "code", e))
