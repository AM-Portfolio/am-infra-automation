#!/usr/bin/env python3
"""Refresh ghcr-creds / github-registry-secret / regcred from ~/.asrax/credentials.env (no token printed)."""
from __future__ import annotations

import base64
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

CREDS = Path(os.environ.get("ASRAX_CREDENTIALS", Path.home() / ".asrax" / "credentials.env"))
NS_LIST = os.environ.get("GHCR_NS", "am-apps-prod,am-agents-prod").split(",")
SECRET_NAMES = ["ghcr-creds", "github-registry-secret", "regcred"]


def load_sot() -> tuple[str, str]:
    t = CREDS.read_text(encoding="utf-8")
    user_m = re.search(r"(?m)^GHCR_USERNAME=(.+)$", t) or re.search(r"(?m)^GITHUB_USERNAME=(.+)$", t)
    tok_m = (
        re.search(r"(?m)^GHCR_TOKEN=(.+)$", t)
        or re.search(r"(?m)^GITHUB_PERSONAL_ACCESS_TOKEN=(.+)$", t)
        or re.search(r"(?m)^GITHUB_TOKEN=(.+)$", t)
    )
    if not tok_m:
        raise SystemExit(f"no GHCR/GITHUB token in {CREDS}")
    user = (user_m.group(1) if user_m else "ssd2658").strip().strip('"').strip("'")
    tok = tok_m.group(1).strip().strip('"').strip("'")
    print(f"SoT {CREDS} user={user} token_len={len(tok)} prefix={tok[:7]}")
    return user, tok


def dockerconfig(user: str, tok: str) -> str:
    auth = base64.b64encode(f"{user}:{tok}".encode()).decode()
    return json.dumps({"auths": {"ghcr.io": {"username": user, "password": tok, "auth": auth}}})


def apply_secret(ns: str, name: str, cfg: str) -> None:
    # create or replace
    patch = {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {"name": name, "namespace": ns},
        "type": "kubernetes.io/dockerconfigjson",
        "data": {".dockerconfigjson": base64.b64encode(cfg.encode()).decode()},
    }
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
        json.dump(patch, f)
        path = f.name
    try:
        r = subprocess.run(
            ["kubectl", "apply", "-f", path],
            capture_output=True,
            text=True,
        )
        print(f"  {ns}/{name}: {(r.stdout or r.stderr).strip()}")
        if r.returncode != 0:
            raise SystemExit(r.returncode)
    finally:
        os.unlink(path)


def main() -> None:
    user, tok = load_sot()
    cfg = dockerconfig(user, tok)
    for ns in NS_LIST:
        ns = ns.strip()
        if not ns:
            continue
        print(f"== namespace {ns} ==")
        # ensure ns exists
        chk = subprocess.run(["kubectl", "get", "ns", ns], capture_output=True, text=True)
        if chk.returncode != 0:
            print(f"  skip missing ns")
            continue
        for name in SECRET_NAMES:
            apply_secret(ns, name, cfg)
    print("done")


if __name__ == "__main__":
    main()
