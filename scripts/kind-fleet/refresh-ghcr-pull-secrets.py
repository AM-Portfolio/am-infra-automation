#!/usr/bin/env python3
"""Refresh ghcr-creds / github-registry-secret / regcred (no token printed).

Default SoT: credentials.env. Prefer Vault when USE_VAULT=1 or --vault:
  apps/data/<env>/infra/ghcr (username + token) via kubectl exec on vault-0
  (infra kube context). After seeding, prefer the in-cluster CronJob
  (manifests/ghcr-pull-sync) over this script for day-2.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

CREDS = Path(os.environ.get("ASRAX_CREDENTIALS", Path.home() / ".asrax" / "credentials.env"))
NS_LIST = os.environ.get("GHCR_NS", "am-apps-prod,am-agents-prod,edge").split(",")
SECRET_NAMES = ["ghcr-creds", "github-registry-secret", "regcred"]


def load_sot_env() -> tuple[str, str]:
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


def load_sot_vault(env: str) -> tuple[str, str]:
    out = subprocess.check_output(
        ["kubectl", "-n", "vault", "get", "secret", "vault-unseal-keys", "-o", "json"],
        text=True,
    )
    root = json.loads(base64.b64decode(json.loads(out)["data"]["keys.json"]))["root_token"]
    path = f"{env}/infra/ghcr"
    chk = subprocess.run(
        [
            "kubectl",
            "-n",
            "vault",
            "exec",
            "vault-0",
            "--",
            "env",
            f"VAULT_TOKEN={root}",
            "vault",
            "kv",
            "get",
            "-format=json",
            "-mount=apps",
            path,
        ],
        capture_output=True,
        text=True,
    )
    if chk.returncode != 0:
        raise SystemExit((chk.stderr or chk.stdout or "vault read failed").replace(root, "***"))
    data = (json.loads(chk.stdout).get("data") or {}).get("data") or {}
    user = str(data.get("username") or "token")
    tok = str(data.get("token") or data.get("password") or "")
    if not tok:
        raise SystemExit(f"vault apps/data/{path} missing token")
    print(f"SoT vault apps/data/{path} user={user} token_len={len(tok)} prefix={tok[:7]}")
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
    ap = argparse.ArgumentParser()
    ap.add_argument("--vault", action="store_true", help="Read SoT from Vault apps/<env>/infra/ghcr")
    ap.add_argument("--env", default=os.environ.get("ENV", "prod"))
    ap.add_argument(
        "--apps-context",
        default=os.environ.get("GHCR_APPS_CONTEXT", ""),
        help="kubectl context for applying secrets (default: current; use prod-apps after vault read)",
    )
    args = ap.parse_args()
    use_vault = args.vault or os.environ.get("USE_VAULT", "").lower() in ("1", "true", "yes")
    user, tok = load_sot_vault(args.env) if use_vault else load_sot_env()
    if args.apps_context:
        subprocess.check_call(["kubectl", "config", "use-context", args.apps_context])
        print(f"kubectl context -> {args.apps_context}")
    elif use_vault:
        # Common Contabo split: vault on infra, secrets on apps.
        guess = f"{args.env}-apps" if args.env != "prod" else "prod-apps"
        cur = subprocess.run(
            ["kubectl", "config", "current-context"], capture_output=True, text=True
        )
        if cur.returncode == 0 and "infra" in (cur.stdout or ""):
            subprocess.check_call(["kubectl", "config", "use-context", guess])
            print(f"kubectl context -> {guess} (auto after vault read)")
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
